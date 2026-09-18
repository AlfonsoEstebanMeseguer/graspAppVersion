-- Test del ciclo de vida de las salas de voz (Fase 5, Tarea 5): `room_lifecycle_sweep` y el
-- trigger que purga `room_messages` cuando una sala pasa a 'ended', ejercido por los TRES caminos
-- que pueden disparar esa transición (cron, `room_leave` con host ausente, `room_end`).
--
-- CÓMO SE EJECUTA
--     docker exec -i supabase_db_backend psql -U postgres -d postgres \
--       -v ON_ERROR_STOP=1 < apps/backend/supabase/tests/rooms-lifecycle.sql
--
-- Los relojes se mueven en SQL (`update ... set created_at = now() - interval '3 hours'`), nadie
-- espera dos horas.
create extension if not exists pgtap;

begin;

select plan(18);

-- Semilla. `handle_new_user` exige `display_name` en `raw_user_meta_data` (mismo motivo que en
-- rooms-actions.sql / rooms-rls.sql).
insert into auth.users (id, email, raw_user_meta_data)
  select gen_random_uuid(), 'lc' || g || '@t.dev',
         jsonb_build_object('display_name', 'Persona LC ' || g)
    from generate_series(1, 20) g;
insert into public.categories (id, name, slug)
  values ('44444444-4444-4444-4444-444444444444', 'Ciclo de vida test', 'ciclo-vida-test');

create temp table ids as
  select id, row_number() over (order by email) as n from auth.users where email like 'lc%@t.dev';

-- ============================================================================================
-- Sala A: created_at hace 3h -> 'expired'. El host se queda dentro (participante vivo): el
-- vencimiento por 2h no depende de si hay gente o no.
-- ============================================================================================
select room_create((select id from ids where n = 1), 'Sala A: vencida',
                    '44444444-4444-4444-4444-444444444444') as a \gset
update rooms set created_at = now() - interval '3 hours',
                  last_activity_at = now() - interval '3 hours'
 where id = :'a'::uuid;
-- Mensaje de control para el camino 1 (cron): tiene que desaparecer cuando A se cierre.
insert into room_messages (room_id, sender_id, body)
  values (:'a'::uuid, (select id from ids where n = 1), 'hola desde A');

-- ============================================================================================
-- Sala B: sin participantes vivos desde hace 15 min -> 'empty'. El host permanece en la sala (no
-- pasa por `room_leave`, que terminaría la sala como 'host_left' en vez de dejarla para el
-- barrido) -- se manipula `left_at` directamente, como haría cualquier otro camino que vacíe la
-- sala sin pasar por las funciones de escritura.
-- ============================================================================================
select room_create((select id from ids where n = 2), 'Sala B: vacia',
                    '44444444-4444-4444-4444-444444444444') as b \gset
select room_join((select id from ids where n = 3), :'b'::uuid);
update room_participants set left_at = now() - interval '15 minutes' where room_id = :'b'::uuid;

-- ============================================================================================
-- Sala C: last_activity_at hace 15 min, con gente viva -> 'idle'.
-- ============================================================================================
select room_create((select id from ids where n = 4), 'Sala C: inactiva',
                    '44444444-4444-4444-4444-444444444444') as c \gset
select room_join((select id from ids where n = 5), :'c'::uuid);
update rooms set last_activity_at = now() - interval '15 minutes' where id = :'c'::uuid;

-- ============================================================================================
-- Sala D: recien creada y con gente -> sigue viva. Es el control positivo para el borrado de
-- mensajes: si D no se cierra, su mensaje tiene que seguir ahí tras el barrido.
-- ============================================================================================
select room_create((select id from ids where n = 6), 'Sala D: sana',
                    '44444444-4444-4444-4444-444444444444') as d \gset
select room_join((select id from ids where n = 7), :'d'::uuid);
insert into room_messages (room_id, sender_id, body)
  values (:'d'::uuid, (select id from ids where n = 6), 'hola desde D');

-- ============================================================================================
-- Sala E [el caso que pilla el reloj mal puesto]: se vació hace 1 minuto, NO hace 10. Si
-- "vacia 10 min" se implementara sin reloj propio (disparando en cuanto no hay participantes,
-- sin mirar desde cuándo), esta sala se cerraría en el mismo barrido en el que nace -- y es
-- justo el fallo que `empty_since` (coalesce del último `left_at`, o `created_at` si nunca hubo
-- ninguno) evita.
-- ============================================================================================
select room_create((select id from ids where n = 8), 'Sala E: recien vaciada',
                    '44444444-4444-4444-4444-444444444444') as e \gset
update room_participants set left_at = now() - interval '1 minute' where room_id = :'e'::uuid;

-- ============================================================================================
-- Primera pasada del barrido, límite generoso (100): cierra A, B, C; deja D y E vivas.
-- ============================================================================================
create temp table sweep1 as select * from room_lifecycle_sweep(100);

select is((select ended_reason from rooms where id = :'a'::uuid), 'expired',
          'caso 1: a las 2h se cierra por expired');
select is((select ended_reason from rooms where id = :'b'::uuid), 'empty',
          'caso 2: vacia 10 min se cierra por empty');
select is((select ended_reason from rooms where id = :'c'::uuid), 'idle',
          'caso 3: sin actividad 10 min se cierra por idle');
select is((select status from rooms where id = :'d'::uuid), 'live',
          'caso 4: la sala sana sigue viva');
select is((select status from rooms where id = :'e'::uuid), 'live',
          'caso 5: la sala vaciada hace 1 minuto NO se cierra -- el reloj de "empty" es propio, '
          'no "sin participantes ahora mismo"');

select is((select closed from sweep1), 3,
          'caso 6: el barrido cierra exactamente A, B y C (3), ni una sala sana de mas');
select is((select capped from sweep1), false,
          'caso 7: con limite 100 y solo 3 vencidas, capped=false -- no hizo falta acotar');

-- Camino 1 (cron): el mensaje de A desapareció al cerrarse la sala.
select is((select count(*)::int from room_messages where room_id = :'a'::uuid), 0,
          'caso 8: el trigger borra los mensajes de A cuando el CRON la cierra');
-- Control: el mensaje de D (sigue viva) NO desaparece -- sin este caso, "caso 8" en 0 podria
-- deberse a que el trigger borra CUALQUIER mensaje, no solo el de la sala que se cierra.
select is((select count(*)::int from room_messages where room_id = :'d'::uuid), 1,
          'control del caso 8: el mensaje de D, que sigue viva, no se toca');

-- ============================================================================================
-- El freno ACOTA, no aborta: 3 salas vencidas mas, barrido con limite 2.
-- ============================================================================================
select room_create((select id from ids where n = 9), 'Sala CAP 1',
                    '44444444-4444-4444-4444-444444444444') as cap1 \gset
select room_create((select id from ids where n = 10), 'Sala CAP 2',
                    '44444444-4444-4444-4444-444444444444') as cap2 \gset
select room_create((select id from ids where n = 11), 'Sala CAP 3',
                    '44444444-4444-4444-4444-444444444444') as cap3 \gset
update rooms set created_at = now() - interval '3 hours'
 where id in (:'cap1'::uuid, :'cap2'::uuid, :'cap3'::uuid);

create temp table sweep2 as select * from room_lifecycle_sweep(2);

select is((select closed from sweep2), 2,
          'caso 9: con 3 salas vencidas y limite 2, el barrido cierra exactamente 2');
select is((select capped from sweep2), true,
          'caso 10: capped=true -- quedaba trabajo pendiente para la proxima pasada');
select is(
  (select count(*)::int from rooms
    where id in (:'cap1'::uuid, :'cap2'::uuid, :'cap3'::uuid) and status = 'live'),
  1,
  'caso 11: el freno ACOTA (queda 1 sala viva de las 3), no ABORTA (no quedan las 3 vivas)'
);

-- ============================================================================================
-- Camino 2 (`room_end`, el host termina la sala): el trigger tambien la cubre.
-- ============================================================================================
select room_create((select id from ids where n = 12), 'Sala F: la termina el host',
                    '44444444-4444-4444-4444-444444444444') as f \gset
insert into room_messages (room_id, sender_id, body)
  values (:'f'::uuid, (select id from ids where n = 12), 'hola desde F');
select room_end((select id from ids where n = 12), :'f'::uuid);

select is((select ended_reason from rooms where id = :'f'::uuid), 'host_ended',
          'caso 12: room_end deja ended_reason = host_ended (camino 2, no lo toca el cron)');
select is((select count(*)::int from room_messages where room_id = :'f'::uuid), 0,
          'caso 13: el trigger borra los mensajes de F cuando el HOST la termina (room_end)');

-- ============================================================================================
-- Camino 3 (`room_leave`, se va el host): el trigger tambien la cubre.
-- ============================================================================================
select room_create((select id from ids where n = 13), 'Sala G: el host se va',
                    '44444444-4444-4444-4444-444444444444') as g \gset
insert into room_messages (room_id, sender_id, body)
  values (:'g'::uuid, (select id from ids where n = 13), 'hola desde G');
select room_leave((select id from ids where n = 13), :'g'::uuid);

select is((select ended_reason from rooms where id = :'g'::uuid), 'host_left',
          'caso 14: room_leave del host deja ended_reason = host_left (camino 3)');
select is((select count(*)::int from room_messages where room_id = :'g'::uuid), 0,
          'caso 15: el trigger borra los mensajes de G cuando el HOST se va (room_leave)');

-- ============================================================================================
-- Caso 16-17 [grant, mismo precedente que rooms-actions.sql caso 8]: `room-lifecycle-cron` llama
-- con `getServiceRoleClient()`. Ningun caso de arriba lo detecta porque corren como `postgres`,
-- el dueño de la funcion, que nunca necesita el grant -- hace falta cambiar de rol de verdad.
-- ============================================================================================
create temp table service_role_check (succeeded boolean, err text);
do $$
declare
  v_ok boolean := false;
  v_err text := null;
begin
  begin
    set local role service_role;
    perform room_lifecycle_sweep(1);
    v_ok := true;
  exception when others then
    v_err := sqlerrm;
  end;
  reset role;
  insert into service_role_check values (v_ok, v_err);
end $$;
select ok(
  (select succeeded from service_role_check),
  format('caso 16: service_role puede ejecutar room_lifecycle_sweep (err: %s)',
         coalesce((select err from service_role_check), 'ninguno'))
);

-- `information_schema.routine_privileges` es la autoridad para el grant, no la migracion (punto
-- 11 de rls-security): se consulta bajo `postgres` (nadie cambia de rol para leer un catalogo),
-- confirmando lo que el caso 16 ya demostro por comportamiento.
select ok(
  exists (
    select 1 from information_schema.routine_privileges
     where routine_schema = 'public'
       and routine_name = 'room_lifecycle_sweep'
       and grantee = 'service_role'
       and privilege_type = 'EXECUTE'
  ),
  'caso 17: information_schema confirma el EXECUTE de service_role sobre room_lifecycle_sweep'
);

select * from finish();
rollback;
