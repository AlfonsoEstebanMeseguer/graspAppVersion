-- Test de `public.connect_eligible_sample` (punto 16 de pending-messaging).
--
-- LO QUE SE PRUEBA AQUÍ es que las siete exclusiones viajaron a SQL sin perderse ninguna. Cada caso
-- tiene DOS mitades y la segunda es la que le da sentido: se afirma que la persona NO sale tras
-- sembrar la relación, Y que SÍ salía antes. Sin el control, un caso pasa por vacuidad en cuanto la
-- muestra venga vacía por cualquier motivo — que es exactamente como tres casillas del §12 salieron
-- verdes sin probar nada.
--
-- CÓMO SE EJECUTA
--     docker exec -i supabase_db_backend psql -U postgres -d postgres \
--       -v ON_ERROR_STOP=1 < apps/backend/supabase/tests/connect-eligible-sample.sql
--
-- Todo corre dentro de una transacción que termina en ROLLBACK: no deja rastro.

begin;

-- =====================================================================================
-- Caso 0: dos cuentas, V (espectador) y O (el otro). O es elegible de partida.
-- =====================================================================================
do $$
declare
  v uuid := 'aaaaaaaa-0016-4000-8000-00000000000a';
  o uuid := 'bbbbbbbb-0016-4000-8000-00000000000b';
begin
  insert into auth.users (id, email, raw_user_meta_data)
  values (v, 'v16@grasp.test', '{"display_name":"Vic 16"}'::jsonb),
         (o, 'o16@grasp.test', '{"display_name":"Oti 16"}'::jsonb);

  assert exists (select 1 from public.connect_eligible_sample(v, 100) where user_id = o),
    'CONTROL DE PARTIDA: O debe ser elegible antes de sembrar ninguna relacion';

  raise notice 'Caso 0 OK: el escenario esta sano';
end $$;

-- =====================================================================================
-- Caso 1: RN-47(2) mitad A — el espectador bloqueó a O
-- =====================================================================================
do $$
declare
  v uuid := 'aaaaaaaa-0016-4000-8000-00000000000a';
  o uuid := 'bbbbbbbb-0016-4000-8000-00000000000b';
begin
  assert exists (select 1 from public.connect_eligible_sample(v, 100) where user_id = o),
    'control: O sale antes del bloqueo';

  insert into public.blocks (blocker_id, blocked_id) values (v, o);

  assert not exists (select 1 from public.connect_eligible_sample(v, 100) where user_id = o),
    'RN-47(2)A: a quien bloqueo el espectador NO debe salir';

  delete from public.blocks where blocker_id = v and blocked_id = o;
  raise notice 'Caso 1 OK';
end $$;

-- =====================================================================================
-- Caso 2: RN-47(2) mitad B — O bloqueó al espectador (LA QUE SE OLVIDA)
-- =====================================================================================
do $$
declare
  v uuid := 'aaaaaaaa-0016-4000-8000-00000000000a';
  o uuid := 'bbbbbbbb-0016-4000-8000-00000000000b';
begin
  assert exists (select 1 from public.connect_eligible_sample(v, 100) where user_id = o),
    'control: O sale antes del bloqueo inverso';

  insert into public.blocks (blocker_id, blocked_id) values (o, v);

  assert not exists (select 1 from public.connect_eligible_sample(v, 100) where user_id = o),
    'RN-47(2)B: quien bloqueo AL espectador tampoco debe salir. Esta es la mitad que no se ve '
    'desde la propia lista, porque blocks solo lo lee su blocker_id';

  delete from public.blocks where blocker_id = o and blocked_id = v;
  raise notice 'Caso 2 OK';
end $$;

-- =====================================================================================
-- Caso 3: RN-47(3) — conversación en cualquier estado
-- =====================================================================================
do $$
declare
  v uuid := 'aaaaaaaa-0016-4000-8000-00000000000a';
  o uuid := 'bbbbbbbb-0016-4000-8000-00000000000b';
  c uuid;
  a uuid; b uuid;
begin
  assert exists (select 1 from public.connect_eligible_sample(v, 100) where user_id = o),
    'control: O sale antes de la conversacion';

  -- `conversations` guarda el par ORDENADO (user_a_id < user_b_id).
  a := least(v, o); b := greatest(v, o);
  insert into public.conversations (user_a_id, user_b_id, initiator_id, status)
  values (a, b, v, 'ignored') returning id into c;

  assert not exists (select 1 from public.connect_eligible_sample(v, 100) where user_id = o),
    'RN-47(3): con conversacion existente NO debe salir, ni siquiera si esta ignorada';

  delete from public.conversations where id = c;
  raise notice 'Caso 3 OK';
end $$;

-- =====================================================================================
-- Caso 4: RN-47(5) — a quien ya sigue
-- =====================================================================================
do $$
declare
  v uuid := 'aaaaaaaa-0016-4000-8000-00000000000a';
  o uuid := 'bbbbbbbb-0016-4000-8000-00000000000b';
begin
  assert exists (select 1 from public.connect_eligible_sample(v, 100) where user_id = o),
    'control: O sale antes del follow';

  insert into public.user_follows (follower_id, followee_id, status) values (v, o, 'pending');

  assert not exists (select 1 from public.connect_eligible_sample(v, 100) where user_id = o),
    'RN-47(5): a quien ya sigue NO debe salir, ni con el follow en pending';

  delete from public.user_follows where follower_id = v and followee_id = o;
  raise notice 'Caso 4 OK';
end $$;

-- =====================================================================================
-- Caso 5: RN-47(6) — descartado con «No mostrar más»
-- =====================================================================================
do $$
declare
  v uuid := 'aaaaaaaa-0016-4000-8000-00000000000a';
  o uuid := 'bbbbbbbb-0016-4000-8000-00000000000b';
begin
  assert exists (select 1 from public.connect_eligible_sample(v, 100) where user_id = o),
    'control: O sale antes del descarte';

  insert into public.connect_dismissals (user_id, dismissed_user_id) values (v, o);

  assert not exists (select 1 from public.connect_eligible_sample(v, 100) where user_id = o),
    'RN-47(6): a quien se descarto NO debe salir';

  delete from public.connect_dismissals where user_id = v and dismissed_user_id = o;
  raise notice 'Caso 5 OK';
end $$;

-- =====================================================================================
-- Caso 6: RN-46 — ya se le enseñó HOY, y AYER no cuenta
-- =====================================================================================
do $$
declare
  v uuid := 'aaaaaaaa-0016-4000-8000-00000000000a';
  o uuid := 'bbbbbbbb-0016-4000-8000-00000000000b';
begin
  assert exists (select 1 from public.connect_eligible_sample(v, 100) where user_id = o),
    'control: O sale antes de la impresion';

  -- Una impresion de AYER no debe excluir: la fecha va en la PK y caduca a medianoche.
  insert into public.connect_impressions (user_id, shown_user_id, shown_on)
  values (v, o, current_date - 1);
  assert exists (select 1 from public.connect_eligible_sample(v, 100) where user_id = o),
    'RN-46: una impresion de AYER no debe excluir — caduca a medianoche';

  insert into public.connect_impressions (user_id, shown_user_id, shown_on)
  values (v, o, current_date);
  assert not exists (select 1 from public.connect_eligible_sample(v, 100) where user_id = o),
    'RN-46: a quien ya se enseño HOY NO debe salir';

  delete from public.connect_impressions where user_id = v and shown_user_id = o;
  raise notice 'Caso 6 OK';
end $$;

-- =====================================================================================
-- Caso 7: el espectador nunca se ve a sí mismo
-- =====================================================================================
do $$
declare
  v uuid := 'aaaaaaaa-0016-4000-8000-00000000000a';
begin
  assert not exists (select 1 from public.connect_eligible_sample(v, 100) where user_id = v),
    'el espectador no debe salir en su propio feed';

  raise notice 'Caso 7 OK';
end $$;

-- =====================================================================================
-- Caso 8: GRANTS — solo `service_role` puede ejecutarla
-- =====================================================================================
-- Sin esto la funcion es una fuga: recibe el espectador por parametro, asi que cualquier usuario
-- registrado podria llamarla con el uuid de otro y deducir a quien ha bloqueado, con quien habla y
-- a quien ha descartado.
do $$
declare
  v_oid oid;
begin
  reset role;   -- `set local role` dura toda la TRANSACCION: sin esto se hereda el rol anterior

  select p.oid into v_oid
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'connect_eligible_sample';

  assert v_oid is not null, 'la funcion connect_eligible_sample no existe';
  assert has_function_privilege('service_role',  v_oid, 'EXECUTE'),
    'service_role necesita EXECUTE o connect-feed devuelve 500';
  assert not has_function_privilege('authenticated', v_oid, 'EXECUTE'),
    'authenticated NO debe poder ejecutarla: recibe el espectador por parametro';
  assert not has_function_privilege('anon', v_oid, 'EXECUTE'),
    'anon NO debe poder ejecutarla';

  raise notice 'Caso 8 OK: solo service_role la ejecuta';
end $$;

rollback;
