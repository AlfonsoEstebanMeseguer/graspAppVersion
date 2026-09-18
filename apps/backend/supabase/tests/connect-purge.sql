-- Test de las tablas de Conectar y su purga (Fase 4, Tarea 5).
--
-- Este fichero existe sobre todo por UN motivo: **la purga es el punto del proyecto donde un fallo
-- sería mudo**. Un cron mal programado no da error en ningún sitio — se programa igual de bien con
-- el nombre de función mal escrito, y falla en silencio cada madrugada a las 4:30 sin que nadie
-- mire `cron.job_run_details`. Y el precedente ya existe: el cron de RGPD estuvo declarado en
-- `config.toml` durante todo el Bloque 3 SIN EXISTIR en ningún entorno.
--
-- Por eso el caso 3 no ejecuta una copia a mano del `delete`, sino **el comando literal guardado en
-- `cron.job.command`**. Si alguien renombra `private.purge_connect_tables` y no toca el
-- `cron.schedule`, este test se pone rojo; una copia a mano seguiría verde y el cron seguiría roto.
--
-- CÓMO SE EJECUTA
--     docker exec -i supabase_db_backend psql -U postgres -d postgres \
--       -v ON_ERROR_STOP=1 < apps/backend/supabase/tests/connect-purge.sql
--
-- Todo corre dentro de una transacción que termina en ROLLBACK: no deja rastro.

begin;

-- =====================================================================================
-- Caso 0: dos usuarios y filas de varias edades en las tres tablas
-- =====================================================================================
do $$
declare
  v_a uuid := 'aaaaaaaa-0005-0000-0000-00000000000a';
  v_b uuid := 'bbbbbbbb-0005-0000-0000-00000000000b';
begin
  insert into auth.users (id, email, raw_user_meta_data) values
    (v_a, 'a-con@example.test', '{"display_name":"Ana"}'::jsonb),
    (v_b, 'b-con@example.test', '{"display_name":"Bruno"}'::jsonb);

  -- Impresiones: una de hoy, una de hace 7 dias (en el borde, NO se purga) y una de hace 8.
  insert into public.connect_impressions (user_id, shown_user_id, shown_on) values
    (v_a, v_b, current_date),
    (v_a, v_b, current_date - 7),
    (v_a, v_b, current_date - 8);

  insert into public.connect_feed_runs (user_id, ran_on, refresh_count) values
    (v_a, current_date, 3),
    (v_a, current_date - 8, 5);

  -- Un rechazo, que NO debe purgarse nunca (RN-48).
  insert into public.connect_dismissals (user_id, dismissed_user_id) values (v_a, v_b);

  raise notice 'Caso 0 OK: filas de varias edades en las tres tablas';
end $$;

-- =====================================================================================
-- Caso 1: el job existe, está activo y apunta al esquema `private`
-- =====================================================================================
do $$
declare
  v_cmd  text;
  v_sched text;
  v_activo boolean;
begin
  select command, schedule, active into v_cmd, v_sched, v_activo
    from cron.job where jobname = 'connect-purge';

  assert v_cmd is not null,
    'El cron connect-purge debe estar programado EN UNA MIGRACION. Si falta, revisa que no se haya '
    'declarado en config.toml: el CLI ignora esa clave EN SILENCIO (punto 11b de db-schema)';
  assert v_activo, 'El cron connect-purge debe estar activo';
  assert v_sched = '30 4 * * *', 'El cron debe correr a las 04:30 UTC; corre a: ' || v_sched;
  -- En `public` PostgREST lo expondria como RPC y seria un disparador publico de un job interno.
  assert v_cmd like '%private.%',
    'El envoltorio del cron debe vivir en el esquema private, no en public; el comando es: ' || v_cmd;

  raise notice 'Caso 1 OK: connect-purge programado, activo y en private';
end $$;

-- =====================================================================================
-- Caso 2: las tres tablas no tienen grants para authenticated ni anon, y RLS está activo
-- =====================================================================================
do $$
declare
  v_privs text;
  v_sin_rls text;
begin
  select coalesce(string_agg(distinct table_name || ':' || grantee, ', '), '(ninguno)')
    into v_privs
    from information_schema.table_privileges
   where table_schema = 'public'
     and table_name in ('connect_dismissals', 'connect_impressions', 'connect_feed_runs')
     and grantee in ('anon', 'authenticated');

  assert v_privs = '(ninguno)',
    'Las tablas de Conectar no deben tener grants para anon/authenticated; tienen: ' || v_privs;

  select coalesce(string_agg(c.relname, ', '), '(ninguna)') into v_sin_rls
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public'
     and c.relname in ('connect_dismissals', 'connect_impressions', 'connect_feed_runs')
     and not c.relrowsecurity;

  assert v_sin_rls = '(ninguna)', 'Estas tablas deben tener RLS activo; sin RLS: ' || v_sin_rls;

  raise notice 'Caso 2 OK: sin grants de cliente y con RLS activo';
end $$;

-- =====================================================================================
-- Caso 3: EL COMANDO GUARDADO EN cron.job purga lo viejo y respeta lo reciente
-- =====================================================================================
-- Se ejecuta `cron.job.command` literalmente. Es la unica forma de que este test detecte que
-- alguien renombro la funcion y dejo el schedule apuntando al nombre viejo.
do $$
declare
  v_cmd text;
  v_a uuid := 'aaaaaaaa-0005-0000-0000-00000000000a';
  v_imp_hoy   int;
  v_imp_7     int;
  v_imp_8     int;
  v_runs_hoy  int;
  v_runs_8    int;
begin
  select command into v_cmd from cron.job where jobname = 'connect-purge';
  execute v_cmd;

  -- ACOTADO A `v_a`, Y NO ES UN DETALLE. Estos contadores eran GLOBALES, así que cualquier fila que
  -- hubiera dejado otra cosa —navegar por Conectar en el emulador, otra suite, una auditoría— ponía
  -- el caso en rojo sin que nada estuviera roto. Pasó dos veces el 2026-08-28 (61 impresiones de una
  -- auditoría del §12) y cada rojo cuesta averiguar que no significa nada, que es exactamente cómo
  -- un test deja de leerse. Un test comprueba SUS filas; las de los demás no son asunto suyo.
  select count(*) into v_imp_hoy from public.connect_impressions
   where shown_on = current_date and user_id = v_a;
  select count(*) into v_imp_7   from public.connect_impressions
   where shown_on = current_date - 7 and user_id = v_a;
  select count(*) into v_imp_8   from public.connect_impressions
   where shown_on = current_date - 8 and user_id = v_a;
  select count(*) into v_runs_hoy from public.connect_feed_runs
   where ran_on = current_date and user_id = v_a;
  select count(*) into v_runs_8   from public.connect_feed_runs
   where ran_on = current_date - 8 and user_id = v_a;

  assert v_imp_hoy = 1, 'La impresion de hoy debe sobrevivir; quedan: ' || v_imp_hoy;
  assert v_imp_7   = 1, 'La impresion de hace 7 dias esta en el borde y NO se purga; quedan: ' || v_imp_7;
  assert v_imp_8   = 0, 'La impresion de hace 8 dias debe purgarse; quedan: ' || v_imp_8;
  assert v_runs_hoy = 1, 'El run de hoy debe sobrevivir; quedan: ' || v_runs_hoy;
  assert v_runs_8   = 0, 'El run de hace 8 dias debe purgarse; quedan: ' || v_runs_8;

  raise notice 'Caso 3 OK: el comando REAL del cron purga lo viejo y respeta lo reciente';
end $$;

-- =====================================================================================
-- Caso 4: RN-48 — un "No mostrar más" no caduca nunca, así que la purga no lo toca
-- =====================================================================================
do $$
declare
  v_quedan int;
begin
  -- Acotado por lo mismo que el caso 3: un rechazo de otra cuenta no dice nada sobre esta regla.
  select count(*) into v_quedan from public.connect_dismissals
   where user_id = 'aaaaaaaa-0005-0000-0000-00000000000a';

  assert v_quedan = 1,
    'RN-48: los rechazos de Conectar no caducan, la purga no debe tocarlos; quedan: ' || v_quedan;

  -- Y la tabla no tiene ninguna columna de fecha, que es lo que hace imposible purgarla por error.
  assert not exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'connect_dismissals'
       and data_type in ('date', 'timestamp with time zone', 'timestamp without time zone')
  ), 'connect_dismissals no debe tener columna de fecha: nadie la leeria (RN-48, punto 8 de db-schema)';

  raise notice 'Caso 4 OK: los rechazos sobreviven a la purga (RN-48)';
end $$;

-- =====================================================================================
-- Caso 5: RN-46 — la fecha dentro de la PK impide reponer hoy y lo permite mañana
-- =====================================================================================
do $$
declare
  v_hoy_rechazado boolean := false;
begin
  -- Repetir la impresion de HOY choca con la PK: no se puede volver a enseñar a alguien hoy.
  begin
    insert into public.connect_impressions (user_id, shown_user_id, shown_on)
    values ('aaaaaaaa-0005-0000-0000-00000000000a', 'bbbbbbbb-0005-0000-0000-00000000000b',
            current_date);
  exception when others then
    v_hoy_rechazado := true;
  end;

  assert v_hoy_rechazado, 'Repetir la impresion de hoy debe chocar con la PK (RN-46)';

  -- La de MAÑANA entra sin problema: la caducidad la hace el calendario, no el codigo.
  insert into public.connect_impressions (user_id, shown_user_id, shown_on)
  values ('aaaaaaaa-0005-0000-0000-00000000000a', 'bbbbbbbb-0005-0000-0000-00000000000b',
          current_date + 1);

  raise notice 'Caso 5 OK: la PK con la fecha dentro ES la logica de caducidad (RN-46)';
end $$;

-- =====================================================================================
-- Caso 6: un usuario autenticado no puede leer ninguna de las tres
-- =====================================================================================
do $$
declare
  v_rechazos int := 0;
  v_t text;
begin
  set local role authenticated;
  set local request.jwt.claims = '{"sub":"aaaaaaaa-0005-0000-0000-00000000000a"}';

  foreach v_t in array array['connect_dismissals', 'connect_impressions', 'connect_feed_runs'] loop
    begin
      execute format('select 1 from public.%I limit 1', v_t);
    exception when others then
      v_rechazos := v_rechazos + 1;
    end;
  end loop;

  reset role;

  assert v_rechazos = 3,
    'Las tres tablas deben ser inaccesibles para authenticated; rechazaron: ' || v_rechazos || ' de 3';

  raise notice 'Caso 6 OK: authenticated no lee ninguna de las tres';
end $$;

rollback;
