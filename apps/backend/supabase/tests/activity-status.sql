-- Test de los RPC del punto de actividad (Fase 4, Tarea 4): `touch_last_seen` y `activity_status`.
--
-- Lo que se prueba aquí no es "la función devuelve lo esperado", sino las dos cosas que sostienen
-- la decisión de diseño de la Tarea 1 (meter `last_seen_at` en `profiles_private` y no en
-- `profiles`):
--
--   1. NINGÚN camino devuelve una marca de tiempo. Si algún día alguien "mejora" el RPC para
--      devolver `last_seen_at` o un "hace N minutos", el caso 6 se pone en rojo.
--   2. RN-32 es RECÍPROCO y se aplica DENTRO de la función: quien oculta su actividad tampoco ve
--      la de los demás. Si esa regla se subiera a la Edge Function, bastaría una llamada directa
--      al RPC —que `authenticated` puede hacer— para saltársela. El caso 3 lo fija.
--
-- CÓMO SE EJECUTA
--     docker exec -i supabase_db_backend psql -U postgres -d postgres \
--       -v ON_ERROR_STOP=1 < apps/backend/supabase/tests/activity-status.sql
--
-- Todo corre dentro de una transacción que termina en ROLLBACK: no deja rastro.
--
-- LOS TRES USUARIOS (los del plan)
--   A — activo, no oculta.
--   B — activo, PERO con `hide_activity_status = true`.
--   C — inactivo (su último latido es de hace una hora).

begin;

-- =====================================================================================
-- Caso 0: alta de los tres y estado de partida
-- =====================================================================================
do $$
declare
  v_a uuid := 'aaaaaaaa-0004-0000-0000-00000000000a';
  v_b uuid := 'bbbbbbbb-0004-0000-0000-00000000000b';
  v_c uuid := 'cccccccc-0004-0000-0000-00000000000c';
begin
  insert into auth.users (id, email, raw_user_meta_data) values
    (v_a, 'a-act@example.test', '{"display_name":"Ana"}'::jsonb),
    (v_b, 'b-act@example.test', '{"display_name":"Bruno"}'::jsonb),
    (v_c, 'c-act@example.test', '{"display_name":"Carla"}'::jsonb);

  update public.profiles_private set last_seen_at = now() where user_id = v_a;
  update public.profiles_private set last_seen_at = now(), hide_activity_status = true
   where user_id = v_b;
  update public.profiles_private set last_seen_at = now() - interval '1 hour' where user_id = v_c;

  raise notice 'Caso 0 OK: A activo, B activo pero oculto, C inactivo';
end $$;

-- =====================================================================================
-- Caso 1: A se ve a sí mismo activo, y ve a C en gris
-- =====================================================================================
do $$
declare
  v_a boolean;
  v_c boolean;
begin
  set local role authenticated;
  set local request.jwt.claims = '{"sub":"aaaaaaaa-0004-0000-0000-00000000000a"}';

  select is_active into v_a from public.activity_status(
    array['aaaaaaaa-0004-0000-0000-00000000000a'::uuid]);
  select is_active into v_c from public.activity_status(
    array['cccccccc-0004-0000-0000-00000000000c'::uuid]);

  reset role;

  assert v_a, 'A acaba de latir: debe verse activo';
  assert not v_c, 'C latio hace una hora: debe salir en gris';

  raise notice 'Caso 1 OK: el latido reciente sale verde y el viejo, gris';
end $$;

-- =====================================================================================
-- Caso 2: A ve a B en GRIS aunque B esté activo, porque B lo oculta (RN-32)
-- =====================================================================================
do $$
declare
  v_b boolean;
  v_ultimo_latido_de_b timestamptz;
begin
  -- Se comprueba primero que B SI esta activo de verdad: si no, este caso pasaria por el motivo
  -- equivocado (B gris porque no ha latido, no porque lo oculte) y seria un test vacuo.
  select last_seen_at into v_ultimo_latido_de_b
    from public.profiles_private where user_id = 'bbbbbbbb-0004-0000-0000-00000000000b';
  assert v_ultimo_latido_de_b > now() - interval '2 minutes',
    'Precondicion: B tiene que estar realmente activo para que este caso pruebe lo que dice';

  set local role authenticated;
  set local request.jwt.claims = '{"sub":"aaaaaaaa-0004-0000-0000-00000000000a"}';
  select is_active into v_b from public.activity_status(
    array['bbbbbbbb-0004-0000-0000-00000000000b'::uuid]);
  reset role;

  assert not v_b, 'B esta activo pero lo oculta: A debe verlo en gris (RN-32)';

  raise notice 'Caso 2 OK: quien oculta su actividad sale gris aunque este activo';
end $$;

-- =====================================================================================
-- Caso 3: B, que oculta, ve a TODOS en gris — incluido A, que sí está activo
-- =====================================================================================
-- Es la mitad recíproca de RN-32, y la que se olvida: ocultarse no es solo dejar de emitir, es
-- también dejar de recibir. Vive dentro de la función a proposito.
do $$
declare
  v_activos int;
begin
  set local role authenticated;
  set local request.jwt.claims = '{"sub":"bbbbbbbb-0004-0000-0000-00000000000b"}';

  select count(*) into v_activos
    from public.activity_status(array[
      'aaaaaaaa-0004-0000-0000-00000000000a'::uuid,
      'bbbbbbbb-0004-0000-0000-00000000000b'::uuid,
      'cccccccc-0004-0000-0000-00000000000c'::uuid])
   where is_active;

  reset role;

  assert v_activos = 0,
    'B oculta su actividad: no debe ver activo a NADIE, ni siquiera a A; vio activos: ' || v_activos;

  raise notice 'Caso 3 OK: quien oculta tampoco ve (RN-32 es reciproco)';
end $$;

-- =====================================================================================
-- Caso 4: se devuelve UNA FILA POR ID PEDIDO, en el mismo orden
-- =====================================================================================
-- Si faltasen filas, el cliente no sabría distinguir "gris" de "no me contestaron por este".
do $$
declare
  v_filas int;
  v_desconocido boolean;
begin
  set local role authenticated;
  set local request.jwt.claims = '{"sub":"aaaaaaaa-0004-0000-0000-00000000000a"}';

  select count(*) into v_filas
    from public.activity_status(array[
      'aaaaaaaa-0004-0000-0000-00000000000a'::uuid,
      'bbbbbbbb-0004-0000-0000-00000000000b'::uuid,
      'cccccccc-0004-0000-0000-00000000000c'::uuid,
      '99999999-9999-4999-8999-999999999999'::uuid]);

  -- Un uuid que no existe devuelve lo MISMO que uno inactivo: este RPC no sirve para averiguar
  -- si una cuenta existe.
  select is_active into v_desconocido
    from public.activity_status(array['99999999-9999-4999-8999-999999999999'::uuid]);

  reset role;

  assert v_filas = 4, 'Debe devolver una fila por id pedido; devolvio: ' || v_filas;
  assert not v_desconocido, 'Un uuid inexistente debe salir gris, igual que uno inactivo';

  raise notice 'Caso 4 OK: una fila por id, y el inexistente no se distingue del inactivo';
end $$;

-- =====================================================================================
-- Caso 5: `touch_last_seen` solo toca la fila propia, y solo el reloj
-- =====================================================================================
do $$
declare
  v_c_antes  timestamptz;
  v_c_despues timestamptz;
  v_a_antes   timestamptz;
  v_a_despues timestamptz;
begin
  select last_seen_at into v_c_antes
    from public.profiles_private where user_id = 'cccccccc-0004-0000-0000-00000000000c';
  select last_seen_at into v_a_antes
    from public.profiles_private where user_id = 'aaaaaaaa-0004-0000-0000-00000000000a';

  -- Late C, que estaba inactivo.
  set local role authenticated;
  set local request.jwt.claims = '{"sub":"cccccccc-0004-0000-0000-00000000000c"}';
  perform public.touch_last_seen();
  reset role;

  select last_seen_at into v_c_despues
    from public.profiles_private where user_id = 'cccccccc-0004-0000-0000-00000000000c';
  select last_seen_at into v_a_despues
    from public.profiles_private where user_id = 'aaaaaaaa-0004-0000-0000-00000000000a';

  assert v_c_despues > v_c_antes, 'El latido de C debe adelantar su last_seen_at';
  assert v_c_despues > now() - interval '2 minutes', 'Tras latir, C debe contar como activo';
  -- La fila de A no se toca: la funcion no acepta parametro de usuario, asi que no hay forma de
  -- latir por otro. Se comprueba igualmente, que es lo que convierte la afirmacion en un hecho.
  -- OJO al comparar contra `now()` aqui dentro: dentro de una transaccion `now()` es CONSTANTE (el
  -- instante en que empezo), asi que `v_a_despues < now()` seria falso por igualdad y no por que
  -- la fila hubiera cambiado. Se compara contra el valor capturado antes, que es lo que de verdad
  -- se quiere afirmar.
  assert v_a_despues = v_a_antes, 'El latido de C no debe haber tocado la fila de A';

  raise notice 'Caso 5 OK: el latido solo adelanta la fila propia';
end $$;

-- =====================================================================================
-- Caso 6: NINGÚN camino devuelve una marca de tiempo
-- =====================================================================================
-- Es el caso que protege la decisión de la Tarea 1. Se comprueba contra el catálogo, no contra una
-- llamada concreta: así cubre cualquier futura columna añadida al tipo de retorno.
do $$
declare
  v_tipos text;
begin
  select string_agg(format('%s %s', p.proname, pg_get_function_result(p.oid)), ' / ')
    into v_tipos
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname in ('activity_status', 'touch_last_seen');

  assert v_tipos not like '%timestamp%',
    'Ningun RPC de actividad puede devolver una marca de tiempo; devuelven: ' || v_tipos;
  assert v_tipos not like '%date%',
    'Ningun RPC de actividad puede devolver una fecha; devuelven: ' || v_tipos;

  raise notice 'Caso 6 OK: el tipo de retorno no incluye ninguna marca de tiempo';
end $$;

-- =====================================================================================
-- Caso 7: `anon` no puede ejecutar ninguna de las dos
-- =====================================================================================
do $$
declare
  v_status_rechazado boolean := false;
  v_touch_rechazado  boolean := false;
begin
  set local role anon;
  begin
    perform public.activity_status(array['aaaaaaaa-0004-0000-0000-00000000000a'::uuid]);
  exception when others then
    v_status_rechazado := true;
  end;
  reset role;

  set local role anon;
  begin
    perform public.touch_last_seen();
  exception when others then
    v_touch_rechazado := true;
  end;
  reset role;

  assert v_status_rechazado, 'anon no debe poder ejecutar activity_status';
  assert v_touch_rechazado,  'anon no debe poder ejecutar touch_last_seen';

  raise notice 'Caso 7 OK: anon no ejecuta ninguno de los dos RPC';
end $$;

-- =====================================================================================
-- Caso 8: el tope de 500 ids
-- =====================================================================================
do $$
declare
  v_rechazado boolean := false;
  v_ok        int;
begin
  set local role authenticated;
  set local request.jwt.claims = '{"sub":"aaaaaaaa-0004-0000-0000-00000000000a"}';

  begin
    perform public.activity_status(
      (select array_agg(gen_random_uuid()) from generate_series(1, 501)));
  exception when others then
    v_rechazado := true;
  end;

  select count(*) into v_ok from public.activity_status(
    (select array_agg(gen_random_uuid()) from generate_series(1, 500)));

  reset role;

  assert v_rechazado, '501 ids debe rechazarse';
  assert v_ok = 500,  '500 ids debe aceptarse; devolvio: ' || v_ok;

  raise notice 'Caso 8 OK: el tope de 500 ids rechaza sin truncar en silencio';
end $$;

rollback;
