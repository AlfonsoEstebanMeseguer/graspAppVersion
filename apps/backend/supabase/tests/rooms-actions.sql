-- Test de las funciones de Postgres de room-actions (Fase 5, Tarea 3).
--
-- El aforo y el tope de hablantes se prueban aqui, sobre las funciones de
-- Postgres que hacen el trabajo, porque es ahi donde tienen que ser atomicos.
-- Las reglas de negocio se cuentan DENTRO de la transaccion que escribe:
-- contar fuera y escribir despues es una carrera que dos peticiones
-- simultaneas ganan las dos (el `for update` sobre `rooms` es lo que lo evita).
--
-- CÓMO SE EJECUTA
--     docker exec -i supabase_db_backend psql -U postgres -d postgres \
--       -v ON_ERROR_STOP=1 < apps/backend/supabase/tests/rooms-actions.sql
--
-- `pgtap` se crea AQUI, fuera de cualquier transaccion (autocommit), y no
-- dentro del `begin` de abajo: el caso adicional de concurrencia real del
-- final del fichero corre DESPUES del `rollback` de la suite principal (a
-- proposito, ver esa seccion) y necesita `ok()`/`is()` disponibles ahi
-- tambien. Si `pgtap` solo se creara dentro de la transaccion que hace
-- rollback, dejaria de existir para esa segunda seccion.
create extension if not exists pgtap;

begin;

select plan(13);

-- Semilla. `handle_new_user` exige `display_name` en `raw_user_meta_data`
-- (ADR 0018, punto 4f de db-schema) -- mismo motivo que en rooms-rls.sql.
insert into auth.users (id, email, raw_user_meta_data)
  select gen_random_uuid(), 'u' || g || '@t.dev',
         jsonb_build_object('display_name', 'Persona ' || g)
    from generate_series(1, 25) g;
insert into public.categories (id, name, slug)
  values ('33333333-3333-3333-3333-333333333333', 'Duelo test', 'duelo-test');

create temp table ids as
  select id, row_number() over (order by email) as n from auth.users;

-- Un host y su sala
select room_create(
  (select id from ids where n = 1),
  'Sala de prueba',
  '33333333-3333-3333-3333-333333333333'
) as room_id \gset

-- Caso 0: room_max_occupants() es la autoridad que usan las funciones de
-- abajo -- si esto no da 20, los casos 1 y 2 no estarian probando el tope
-- documentado en la migracion.
select is(room_max_occupants(), 20, 'caso 0: el aforo de una sala es 20');

-- Caso 1: caben 19 mas (20 en total: el host + 19)
--
-- `:'room_id'` no se interpola dentro de un bloque `$$...$$`: psql solo
-- sustituye variables en texto SQL normal, no dentro de comillas de dolar.
-- Por eso se pasa como argumento de `format()`, fuera del bloque `$$...$$`
-- (igual que hacen los casos 2-4 de abajo, que sí funcionan) -- `%L` lo
-- incrusta ya citado, y `id` sigue siendo la referencia de columna de la
-- consulta, no un valor a sustituir.
select lives_ok(
  format($$select room_join(id, %L::uuid) from ids where n between 2 and 20$$,
         :'room_id'),
  'caso 1: entran 19 personas mas, hasta el aforo de 20'
);

-- Caso 2: la 21 no entra
select throws_ok(
  format($$select room_join(%L::uuid, %L::uuid)$$,
         (select id from ids where n = 21), :'room_id'),
  'P0001',
  'room_full',
  'caso 2: la persona 21 no cabe'
);

-- Caso 3: el segundo hablante sube (el host ya cuenta como hablante 1)
select room_raise_hand((select id from ids where n = 2), :'room_id'::uuid, 'quiero hablar');
select lives_ok(
  format($$select room_grant_speak(%L::uuid, %L::uuid, %L::uuid)$$,
         (select id from ids where n = 1), :'room_id',
         (select id from ids where n = 2)),
  'caso 3: con el host hablando, sube un segundo'
);

-- Caso 4: el tercero no
select room_raise_hand((select id from ids where n = 3), :'room_id'::uuid, 'yo tambien');
select throws_ok(
  format($$select room_grant_speak(%L::uuid, %L::uuid, %L::uuid)$$,
         (select id from ids where n = 1), :'room_id',
         (select id from ids where n = 3)),
  'P0001',
  'stage_full',
  'caso 4: un tercer hablante no sube'
);

-- Caso 5: quien no es el host no puede conceder la palabra
select throws_ok(
  format($$select room_grant_speak(%L::uuid, %L::uuid, %L::uuid)$$,
         (select id from ids where n = 2), :'room_id',
         (select id from ids where n = 3)),
  'P0001',
  'not_the_host',
  'caso 5: quien no es el host no puede conceder la palabra'
);

-- Caso 6: el host baja al segundo hablante del escenario, y baja de
-- verdad -- room_revoke_speak no comprueba el tope, solo quien es el host.
select room_revoke_speak(
  (select id from ids where n = 1),
  :'room_id'::uuid,
  (select id from ids where n = 2)
);
select is(
  (select role from public.room_participants
    where room_id = :'room_id'::uuid
      and user_id = (select id from ids where n = 2)
      and left_at is null),
  'listener',
  'caso 6: room_revoke_speak devuelve al segundo hablante a oyente'
);

-- Caso 7: con el escenario liberado por el caso 6, el tercero (que seguia
-- con la mano levantada) ya puede subir -- confirma que revoke_speak no deja
-- el tope bloqueado.
select lives_ok(
  format($$select room_grant_speak(%L::uuid, %L::uuid, %L::uuid)$$,
         (select id from ids where n = 1), :'room_id',
         (select id from ids where n = 3)),
  'caso 7: liberado el escenario, el tercero puede subir'
);

-- Caso 8 [Critical, vuelta de arreglos 1]: `room-actions` llama con
-- `getServiceRoleClient()`, y las seis funciones de escritura llevan
-- `revoke all ... from public, anon, authenticated` -- sin un `grant execute
-- ... to service_role` explicito, `service_role` no puede ejecutarlas
-- (BYPASSRLS no es BYPASSGRANT). NINGUN caso de arriba lo detecta porque
-- corren como `postgres`, el dueño de las funciones, que nunca necesita el
-- grant: hace falta cambiar de rol de verdad para que este caso pueda fallar.
-- `lives_ok` no sirve aqui: su `EXECUTE` interno solo admite una sentencia,
-- y `set local role` + control de transaccion no caben en una. Se hace a
-- mano con un `do $$ ... $$` que cambia de rol, intenta la llamada real y
-- guarda si murió o no en una tabla temporal -- comprobado a mano que este
-- caso SÍ falla si se revoca el `execute` de nuevo (repite el
-- "permission denied for function room_create" exacto que reprodujo la
-- revisión). Se prueba con una sala nueva (n=22, sin usar todavia) para no
-- interferir con el aforo/escenario que ya monto la sala de los casos 1-7.
create temp table service_role_check (succeeded boolean, err text);
do $$
declare
  v_ok boolean := false;
  v_err text := null;
  v_host uuid;
begin
  -- Resolver el id ANTES de cambiar de rol: la tabla temporal `ids` es de
  -- `postgres`, y `service_role` no tiene grant sobre ella -- si se lee
  -- despues del `set local role`, el caso falla por el motivo equivocado
  -- ("permission denied for table ids") y no por lo que se quiere probar.
  select id into v_host from ids where n = 22;
  begin
    set local role service_role;
    perform room_create(
      v_host,
      'Sala de service_role',
      '33333333-3333-3333-3333-333333333333'::uuid
    );
    v_ok := true;
  exception when others then
    v_err := sqlerrm;
  end;
  reset role;
  insert into service_role_check values (v_ok, v_err);
end $$;
select ok(
  (select succeeded from service_role_check),
  format('caso 8: service_role puede ejecutar room_create (err: %s)',
         coalesce((select err from service_role_check), 'ninguno'))
);

-- Caso 9 [Important #2]: reunirse dos veces a la misma sala (doble toque,
-- reintento de red) tiene que dar un error legible, no el 23505 crudo del
-- indice unico parcial `room_participants_one_room_idx`. n=4 ya esta dentro
-- desde el caso 1.
select throws_ok(
  format($$select room_join(%L::uuid, %L::uuid)$$,
         (select id from ids where n = 4), :'room_id'),
  'P0001',
  'already_in_room',
  'caso 9: reunirse dos veces a la misma sala da already_in_room, no un 500 crudo'
);

-- Casos 10-12 [Important #3]: `end` no es un alias de `leave`. Sala aparte
-- (host n=23, participante n=24) para no interferir con la sala de los
-- casos 1-9.
select room_create(
  (select id from ids where n = 23), 'Sala para terminar',
  '33333333-3333-3333-3333-333333333333'
) as end_room_id \gset
select room_join((select id from ids where n = 24), :'end_room_id'::uuid);

-- Caso 10: un participante cualquiera no puede terminar la sala del host.
select throws_ok(
  format($$select room_end(%L::uuid, %L::uuid)$$,
         (select id from ids where n = 24), :'end_room_id'),
  'P0001',
  'not_the_host',
  'caso 10: quien no es el host no puede terminar la sala'
);

-- Caso 11: el host si puede.
select lives_ok(
  format($$select room_end(%L::uuid, %L::uuid)$$,
         (select id from ids where n = 23), :'end_room_id'),
  'caso 11: el host termina la sala'
);

-- Caso 12: y queda registrado como terminada por el host, no como un
-- abandono -- `ended_reason = 'host_ended'` esta en el check del esquema
-- desde el principio y antes de este arreglo no lo escribia ningun camino.
select is(
  (select ended_reason from public.rooms where id = :'end_room_id'::uuid),
  'host_ended',
  'caso 12: room_end deja ended_reason = host_ended'
);

select * from finish();
rollback;

-- ============================================================================
-- Caso adicional [Important #4]: la carrera del aforo con CONCURRENCIA REAL
-- ============================================================================
-- Los 13 casos de arriba corren en una unica sesion secuencial: nunca
-- ejecutan dos `room_join` a la vez, asi que NUNCA pueden detectar que
-- alguien quite el `for update` de `room_join` -- comprobado a mano: con el
-- lock quitado, los 13 casos de arriba siguen dando 13/13 `ok`. Aqui se abre
-- una SEGUNDA conexion real a la misma base de datos con `dblink` para forzar
-- el solape de verdad, en vez de depender de un montaje manual con dos
-- terminales.
--
-- SOLO PARA DESARROLLO LOCAL: la cadena de conexion usa el nombre del
-- contenedor (`supabase_db_backend`, resoluble por el DNS interno de Docker)
-- y la contraseña por defecto del stack local de `supabase start`. No sirve
-- contra un entorno remoto, y no hay CI todavia que la dispare sola
-- (`.github/workflows/` solo tiene un README -- ver CLAUDE.md § Comandos).
--
-- Esta seccion NO esta dentro de la transaccion `begin ... rollback` de
-- arriba: la conexion de dblink es una SESION APARTE y no veria filas sin
-- confirmar de esta. Los INSERT/DELETE de aqui son confirmaciones reales,
-- no cosmeticas -- por eso la limpieza del final es obligatoria, no un gesto.
--
-- El resultado que importa es `got_room_full` (¿la segunda perdió la
-- carrera de verdad?) y el recuento final de ocupantes, NO el tiempo que
-- tardó en bloquearse: se comprobó a mano que ese tiempo ronda ~2s tanto con
-- el `for update` como sin él (el `update rooms set last_activity_at` al
-- final de `room_join` también serializa, por una razón distinta y sin
-- relación con el aforo), así que no discrimina la mutación y no se usa
-- como aserción.
create extension if not exists dblink;

-- Segundo plan pgTAP: el de la suite principal ya se cerró con `finish()`
-- dentro de la transacción que hizo `rollback` (y con ella se deshizo el
-- estado de seguimiento de pgTAP). `ok()`/`is()` exigen un plan activo, así
-- que se abre uno nuevo, propio de esta sección.
select plan(2);

insert into auth.users (id, email, raw_user_meta_data) values
  ('66666666-0000-0000-0000-000000000001', 'race-host@t.dev', '{"display_name":"Race Host"}'::jsonb),
  ('66666666-0000-0000-0000-000000000002', 'race-a@t.dev', '{"display_name":"Race A"}'::jsonb),
  ('66666666-0000-0000-0000-000000000003', 'race-b@t.dev', '{"display_name":"Race B"}'::jsonb);
insert into auth.users (id, email, raw_user_meta_data)
  select ('66666666-0000-0000-0000-0000000001' || lpad(g::text, 2, '0'))::uuid,
         'race-m' || g || '@t.dev', jsonb_build_object('display_name', 'Race M' || g)
    from generate_series(1, 18) g;
insert into public.categories (id, name, slug)
  values ('66666666-6666-6666-6666-666666666666', 'Race concurrency', 'race-concurrency')
  on conflict do nothing;

select room_create('66666666-0000-0000-0000-000000000001'::uuid, 'Sala de la carrera real',
                    '66666666-6666-6666-6666-666666666666'::uuid) as race_room_id \gset
-- host + 18 = 19/20: queda exactamente un hueco para que A y B compitan por el.
select room_join(('66666666-0000-0000-0000-0000000001' || lpad(g::text, 2, '0'))::uuid, :'race_room_id'::uuid)
  from generate_series(1, 18) g;

select dblink_connect('room_race_conn',
  'dbname=postgres user=postgres password=postgres host=supabase_db_backend port=5432 sslmode=disable connect_timeout=5');

-- A entra de forma asincrona en la otra sesion; esa sesion no confirma (no
-- libera ningun lock que tome dentro de room_join) hasta pasados ~2s.
select dblink_send_query('room_race_conn',
  format('do $x$ begin perform room_join(%L::uuid, %L::uuid); perform pg_sleep(2); end $x$;',
         '66666666-0000-0000-0000-000000000002'::uuid, :'race_room_id'));

create temp table race_result (blocked_ms numeric, got_room_full boolean);

-- B intenta el mismo hueco en ESTA sesion, sin ningun retraso artificial de
-- por medio. Si `room_join` sigue teniendo el `for update`, la carrera la
-- gana como mucho una de las dos y B debe recibir `room_full`. Si no lo
-- tiene, las dos pueden colarse (comprobado a mano: `got_room_full` sale
-- `false` y el recuento final da 21).
select format($outer$
do $inner$
declare
  t0 timestamptz := clock_timestamp();
  t1 timestamptz;
  ok_full boolean := false;
begin
  begin
    perform room_join(%L::uuid, %L::uuid);
  exception when others then
    if sqlstate = 'P0001' then
      ok_full := true;
    else
      raise;
    end if;
  end;
  t1 := clock_timestamp();
  insert into race_result values (extract(epoch from (t1 - t0)) * 1000, ok_full);
end
$inner$;
$outer$, '66666666-0000-0000-0000-000000000003'::uuid, :'race_room_id') as race_cmd \gset

:race_cmd

-- Drena el resultado async antes de desconectar: el DO no devuelve filas,
-- asi que basta una lista de columnas dummy para que dblink resuelva el
-- tipo del record generico.
select * from dblink_get_result('room_race_conn') as t(dummy text);
select dblink_disconnect('room_race_conn');

select ok(
  (select got_room_full from race_result),
  'carrera real (dblink): B choca con room_full cuando A ya ocupo el ultimo hueco'
);
select is(
  (select count(*)::int from public.room_participants
    where room_id = :'race_room_id'::uuid and left_at is null),
  20,
  'carrera real (dblink): el aforo final es 20, nunca 21 -- sin sobrebooking'
);

select * from finish();

-- limpieza: los INSERT de esta seccion fueron confirmaciones reales, no
-- dentro de una transaccion que se deshace sola.
delete from public.room_participants where user_id::text like '66666666-%';
delete from public.rooms where host_id::text like '66666666-%';
delete from public.categories where id = '66666666-6666-6666-6666-666666666666'::uuid;
delete from auth.users where id::text like '66666666-%';
