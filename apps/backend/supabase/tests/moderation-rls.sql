-- Test de RLS de `blocks` y `reports` (Fase 4, Tarea 6).
--
-- LO QUE SE PRUEBA AQUÍ ES RN-23, y no se puede probar leyendo la policy. La regla dice que
-- ninguna respuesta puede revelar un bloqueo, «ni por texto ni por forma», y el diseño la cumple
-- por CONSTRUCCIÓN: el bloqueado no tiene fila que consultar. La diferencia entre
-- `using (auth.uid() = blocker_id)` y `using (auth.uid() in (blocker_id, blocked_id))` es una
-- palabra en el SQL y es la regla entera, así que hace falta un test con dos usuarios reales que
-- fije cuál de las dos es.
--
-- CÓMO SE EJECUTA
--     docker exec -i supabase_db_backend psql -U postgres -d postgres \
--       -v ON_ERROR_STOP=1 < apps/backend/supabase/tests/moderation-rls.sql
--
-- Todo corre dentro de una transacción que termina en ROLLBACK: no deja rastro.

begin;

-- =====================================================================================
-- Caso 0: A bloquea y reporta a B. C es un tercero ajeno.
-- =====================================================================================
do $$
declare
  v_a uuid := 'aaaaaaaa-0006-0000-0000-00000000000a';
  v_b uuid := 'bbbbbbbb-0006-0000-0000-00000000000b';
  v_c uuid := 'cccccccc-0006-0000-0000-00000000000c';
  v_conv uuid := '11111111-0006-4000-8000-000000000001';
begin
  insert into auth.users (id, email, raw_user_meta_data) values
    (v_a, 'a-mod@example.test', '{"display_name":"Ana"}'::jsonb),
    (v_b, 'b-mod@example.test', '{"display_name":"Bruno"}'::jsonb),
    (v_c, 'c-mod@example.test', '{"display_name":"Carla"}'::jsonb);

  insert into public.conversations (id, user_a_id, user_b_id, status, initiator_id)
  values (v_conv, v_a, v_b, 'pending', v_a);

  insert into public.blocks (blocker_id, blocked_id) values (v_a, v_b);
  insert into public.reports (reporter_id, reported_id, conversation_id) values (v_a, v_b, v_conv);

  raise notice 'Caso 0 OK: A ha bloqueado y reportado a B';
end $$;

-- =====================================================================================
-- Caso 1: RN-23 — B NO ve la fila en la que A le bloqueó
-- =====================================================================================
-- Es el caso central del fichero. Si esto se pusiera verde con una policy que incluyera
-- `blocked_id`, el bloqueado podria consultar la tabla y descubrir el bloqueo, que es
-- exactamente lo que la regla prohibe.
do $$
declare
  v_b_ve_bloqueos int;
  v_b_ve_reportes int;
begin
  set local role authenticated;
  set local request.jwt.claims = '{"sub":"bbbbbbbb-0006-0000-0000-00000000000b"}';

  -- B busca activamente si alguien le ha bloqueado. No debe encontrar nada.
  select count(*) into v_b_ve_bloqueos from public.blocks;
  select count(*) into v_b_ve_reportes from public.reports;

  reset role;

  assert v_b_ve_bloqueos = 0,
    'RN-23: el bloqueado NO debe ver la fila que le bloquea; vio: ' || v_b_ve_bloqueos;
  assert v_b_ve_reportes = 0,
    'El reportado no debe ver el reporte contra el; vio: ' || v_b_ve_reportes;

  raise notice 'Caso 1 OK: B no tiene fila que consultar (RN-23 por construccion)';
end $$;

-- =====================================================================================
-- Caso 2: A sí ve su propia lista
-- =====================================================================================
-- La otra mitad: la lista existe de verdad para su dueño (decisión 6), aunque todavía no la pinte
-- ninguna pantalla. Sin este caso, una policy que no devolviera nada a nadie también pasaría el 1.
do $$
declare
  v_a_bloqueos int;
  v_a_reportes int;
begin
  set local role authenticated;
  set local request.jwt.claims = '{"sub":"aaaaaaaa-0006-0000-0000-00000000000a"}';
  select count(*) into v_a_bloqueos from public.blocks;
  select count(*) into v_a_reportes from public.reports;
  reset role;

  assert v_a_bloqueos = 1, 'A debe ver a quien ha bloqueado; vio: ' || v_a_bloqueos;
  assert v_a_reportes = 1, 'A debe ver a quien ha reportado; vio: ' || v_a_reportes;

  raise notice 'Caso 2 OK: el dueno si ve su lista';
end $$;

-- =====================================================================================
-- Caso 3: C, ajeno, no ve nada de lo de A y B
-- =====================================================================================
do $$
declare
  v_c_bloqueos int;
  v_c_reportes int;
begin
  set local role authenticated;
  set local request.jwt.claims = '{"sub":"cccccccc-0006-0000-0000-00000000000c"}';
  select count(*) into v_c_bloqueos from public.blocks;
  select count(*) into v_c_reportes from public.reports;
  reset role;

  assert v_c_bloqueos = 0, 'Un tercero no debe ver bloqueos ajenos; vio: ' || v_c_bloqueos;
  assert v_c_reportes = 0, 'Un tercero no debe ver reportes ajenos; vio: ' || v_c_reportes;

  raise notice 'Caso 3 OK: un tercero no ve nada';
end $$;

-- =====================================================================================
-- Caso 4: ningún cliente puede escribir en las dos tablas
-- =====================================================================================
-- Bloquear NO es insertar una fila: tiene efectos en otras tablas (RN-22 archiva la conversación
-- del bloqueador) que deben ocurrir en la misma transacción. Si el cliente pudiera insertar
-- directamente existiría un bloqueo a medias: la fila puesta y la propagación sin hacer.
do $$
declare
  v_block_rechazado  boolean := false;
  v_report_rechazado boolean := false;
  v_borrado_rechazado boolean := false;
begin
  set local role authenticated;
  set local request.jwt.claims = '{"sub":"bbbbbbbb-0006-0000-0000-00000000000b"}';

  begin
    insert into public.blocks (blocker_id, blocked_id)
    values ('bbbbbbbb-0006-0000-0000-00000000000b', 'cccccccc-0006-0000-0000-00000000000c');
  exception when others then
    v_block_rechazado := true;
  end;

  begin
    insert into public.reports (reporter_id, reported_id)
    values ('bbbbbbbb-0006-0000-0000-00000000000b', 'cccccccc-0006-0000-0000-00000000000c');
  exception when others then
    v_report_rechazado := true;
  end;

  reset role;

  -- Y A tampoco puede DESBLOQUEAR por su cuenta. Desde el ADR 0027 el camino de vuelta EXISTE, pero
  -- pasa por `block-remove` con `service_role`, no por PostgREST: desbloquear tiene que ser una
  -- decision del backend igual que bloquearlo. El caso 8 afirma la otra mitad —que service_role si
  -- puede—, sin la cual esto seria cierto por que nadie puede borrar.
  set local role authenticated;
  set local request.jwt.claims = '{"sub":"aaaaaaaa-0006-0000-0000-00000000000a"}';
  begin
    delete from public.blocks where blocker_id = 'aaaaaaaa-0006-0000-0000-00000000000a';
  exception when others then
    v_borrado_rechazado := true;
  end;
  reset role;

  assert v_block_rechazado,  'authenticated no debe poder insertar en blocks';
  assert v_report_rechazado, 'authenticated no debe poder insertar en reports';
  assert v_borrado_rechazado,
    'authenticated no debe poder borrar de blocks: desbloquear pasa por block-remove (ADR 0027)';

  raise notice 'Caso 4 OK: el cliente no escribe ni borra en ninguna de las dos';
end $$;

-- =====================================================================================
-- Caso 5: el índice de la dirección contraria existe (RN-24, RN-47(2))
-- =====================================================================================
-- La PK sirve para "¿a quién he bloqueado yo?". La mitad "en cualquier direccion" consulta por el
-- bloqueado, y la ejecutan CADA envio de mensaje y CADA carga del feed.
do $$
begin
  assert exists (
    select 1 from pg_indexes
     where schemaname = 'public' and tablename = 'blocks' and indexname = 'blocks_blocked_id_idx'
  ), 'Falta blocks_blocked_id_idx: RN-24 consulta por el bloqueado, no por el bloqueador';

  raise notice 'Caso 5 OK: el indice por blocked_id existe';
end $$;

-- =====================================================================================
-- Caso 6: grants — `select` para el dueño, sin `update` para service_role, nada para anon
-- =====================================================================================
do $$
declare
  v_anon text;
  v_sr   text;
begin
  select coalesce(string_agg(distinct table_name, ', '), '(ninguna)') into v_anon
    from information_schema.table_privileges
   where table_schema = 'public' and table_name in ('blocks', 'reports') and grantee = 'anon';

  assert v_anon = '(ninguna)', 'anon no debe tener privilegios aqui; los tiene en: ' || v_anon;

  -- Un bloqueo o un reporte se crean o se retiran, nunca se modifican: no hay ninguna columna que
  -- tenga sentido cambiar despues, asi que `update` no se concede ni a service_role.
  select coalesce(string_agg(distinct table_name, ', '), '(ninguna)') into v_sr
    from information_schema.table_privileges
   where table_schema = 'public' and table_name in ('blocks', 'reports')
     and grantee = 'service_role' and privilege_type = 'UPDATE';

  assert v_sr = '(ninguna)',
    'service_role no necesita UPDATE en estas tablas; lo tiene en: ' || v_sr;

  raise notice 'Caso 6 OK: grants acotados, sin UPDATE ni para service_role';
end $$;

-- =====================================================================================
-- Caso 7: no son tablas lápida — el borrado de cuenta se las lleva (punto 4b de db-schema)
-- =====================================================================================
-- Se prueba por el CAMINO REAL (`delete from auth.users`), no borrando el perfil: son caminos
-- distintos y solo el primero es el del RGPD (punto 4c de db-schema).
do $$
declare
  v_bloqueos int;
  v_reportes int;
begin
  delete from auth.users where id = 'bbbbbbbb-0006-0000-0000-00000000000b';

  -- ACOTADO A LOS USUARIOS DE ESTE TEST, y no `count(*)` sobre la tabla entera.
  --
  -- Hasta el 2026-08-26 esto contaba TODA la tabla, y pasaba solo porque la base venía vacía de un
  -- `db reset`. En cuanto hubo una fila de otra procedencia —un bloqueo creado a mano al verificar
  -- otra cosa— el test se puso rojo señalando una cascada que funcionaba perfectamente. Un test que
  -- depende del estado global de la base da la alarma equivocada, y el día que la dé nadie sabrá si
  -- el fallo es suyo o del código.
  select count(*) into v_bloqueos
    from public.blocks
   where blocker_id in ('aaaaaaaa-0006-0000-0000-00000000000a',
                        'bbbbbbbb-0006-0000-0000-00000000000b',
                        'cccccccc-0006-0000-0000-00000000000c')
      or blocked_id in ('aaaaaaaa-0006-0000-0000-00000000000a',
                        'bbbbbbbb-0006-0000-0000-00000000000b',
                        'cccccccc-0006-0000-0000-00000000000c');

  select count(*) into v_reportes
    from public.reports
   where reporter_id in ('aaaaaaaa-0006-0000-0000-00000000000a',
                         'bbbbbbbb-0006-0000-0000-00000000000b',
                         'cccccccc-0006-0000-0000-00000000000c')
      or reported_id in ('aaaaaaaa-0006-0000-0000-00000000000a',
                         'bbbbbbbb-0006-0000-0000-00000000000b',
                         'cccccccc-0006-0000-0000-00000000000c');

  assert v_bloqueos = 0,
    'Al borrar la cuenta de B, el bloqueo contra el debe irse en cascada; quedan: ' || v_bloqueos;
  assert v_reportes = 0,
    'Al borrar la cuenta de B, el reporte contra el debe irse en cascada; quedan: ' || v_reportes;

  raise notice 'Caso 7 OK: el borrado de cuenta se lleva bloqueos y reportes (no son lapidas)';
end $$;

-- =====================================================================================
-- Caso 8: CONTROL de `block-remove` — `service_role` SI puede borrar de `blocks`
-- =====================================================================================
-- El caso 4 afirma que `authenticated` no puede borrar. Esa afirmacion es compatible con «nadie
-- puede borrar», que dejaria `block-remove` devolviendo 500 sin que ningun test dijera nada. La
-- unica forma de que el caso 4 signifique lo que dice es afirmar tambien la otra mitad.
--
-- `service_role` tiene BYPASSRLS pero NO BYPASSGRANT: se salta las policies de fila, nunca los
-- GRANT de tabla. Por eso esto se consulta y no se supone.
do $$
declare
  v_sr_borra boolean;
  v_auth_borra boolean;
begin
  reset role;   -- `set local role` dura toda la TRANSACCION: sin esto se hereda el rol del caso 7

  v_sr_borra   := has_table_privilege('service_role',  'public.blocks', 'DELETE');
  v_auth_borra := has_table_privilege('authenticated', 'public.blocks', 'DELETE');

  assert v_sr_borra,
    'service_role necesita DELETE sobre blocks o `block-remove` devuelve 500 (ADR 0027)';
  assert not v_auth_borra,
    'authenticated NO debe poder borrar: desbloquear pasa por block-remove, no por PostgREST';

  raise notice 'Caso 8 OK: solo service_role borra de blocks';
end $$;

rollback;
