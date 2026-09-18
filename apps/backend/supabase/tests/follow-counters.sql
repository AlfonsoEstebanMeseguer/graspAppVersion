-- Test de `public.sync_follow_counters` (Fase 4, Tarea 8).
--
-- POR QUÉ ESTA FUNCIÓN RECALCULA EN VEZ DE INCREMENTAR, que es lo que este fichero fija:
-- un `+1` desde la Edge Function sería una carrera (dos aceptaciones simultáneas leen el mismo
-- valor y escriben el mismo incremento), y un contador que deriva no tiene con qué compararse, así
-- que nadie lo detecta. Este repositorio ya borró `badges_count` y `experiences_count` por
-- exactamente eso. Recalcular desde `user_follows` da tres propiedades que un incremento no tiene:
-- es exacto ante concurrencia (una sola sentencia), es idempotente y es AUTOCORRECTIVO.
--
-- CÓMO SE EJECUTA
--     docker exec -i supabase_db_backend psql -U postgres -d postgres \
--       -v ON_ERROR_STOP=1 < apps/backend/supabase/tests/follow-counters.sql

begin;

-- =====================================================================================
-- Caso 0: tres usuarios y un grafo con follows aceptados y pendientes mezclados
-- =====================================================================================
do $$
declare
  a uuid := 'aaaaaaaa-0808-4000-8000-00000000000a';
  b uuid := 'bbbbbbbb-0808-4000-8000-00000000000b';
  c uuid := 'cccccccc-0808-4000-8000-00000000000c';
begin
  insert into auth.users (id, email, raw_user_meta_data) values
    (a, 'a-cnt@example.test', '{"display_name":"Ana"}'::jsonb),
    (b, 'b-cnt@example.test', '{"display_name":"Bruno"}'::jsonb),
    (c, 'c-cnt@example.test', '{"display_name":"Carla"}'::jsonb);

  insert into public.user_follows (follower_id, followee_id, status) values
    (a, b, 'accepted'),   -- A sigue a B
    (c, b, 'accepted'),   -- C sigue a B  -> B tiene 2 seguidores
    (b, c, 'pending');    -- B SOLICITO seguir a C, sin aceptar aun

  raise notice 'Caso 0 OK: grafo con 2 aceptados y 1 pendiente';
end $$;

-- =====================================================================================
-- Caso 1: una solicitud PENDIENTE no cuenta como seguidor
-- =====================================================================================
-- Es la regla que sostiene todo: si contara, cualquiera inflaria su perfil repartiendo
-- solicitudes a desconocidos, sin que ninguno tuviera que aceptar.
do $$
declare
  v_b_followers int;
  v_b_following int;
  v_c_followers int;
begin
  perform public.sync_follow_counters(array[
    'aaaaaaaa-0808-4000-8000-00000000000a'::uuid,
    'bbbbbbbb-0808-4000-8000-00000000000b'::uuid,
    'cccccccc-0808-4000-8000-00000000000c'::uuid]);

  select followers_count, following_count into v_b_followers, v_b_following
    from public.profiles where user_id = 'bbbbbbbb-0808-4000-8000-00000000000b';
  select followers_count into v_c_followers
    from public.profiles where user_id = 'cccccccc-0808-4000-8000-00000000000c';

  assert v_b_followers = 2, 'B debe tener 2 seguidores aceptados; tiene: ' || v_b_followers;
  assert v_b_following = 0,
    'La solicitud PENDIENTE de B a C no debe contar como "siguiendo"; cuenta: ' || v_b_following;
  assert v_c_followers = 0,
    'C no debe tener seguidores: la de B esta pendiente; tiene: ' || v_c_followers;

  raise notice 'Caso 1 OK: solo cuentan los follows aceptados';
end $$;

-- =====================================================================================
-- Caso 2: es AUTOCORRECTIVA — arregla un contador que ya estaba mal
-- =====================================================================================
-- Es la propiedad que un `+1` no puede tener, y la razon principal de este diseño: si un fallo a
-- medias o una escritura vieja dejaron el numero torcido, la siguiente llamada lo endereza sin que
-- nadie tenga que darse cuenta.
do $$
declare
  v_b int;
begin
  update public.profiles set followers_count = 999
   where user_id = 'bbbbbbbb-0808-4000-8000-00000000000b';

  perform public.sync_follow_counters(array['bbbbbbbb-0808-4000-8000-00000000000b'::uuid]);

  select followers_count into v_b
    from public.profiles where user_id = 'bbbbbbbb-0808-4000-8000-00000000000b';

  assert v_b = 2, 'Un contador corrupto debe quedar corregido a 2; quedo: ' || v_b;

  raise notice 'Caso 2 OK: corrige un contador que ya estaba mal';
end $$;

-- =====================================================================================
-- Caso 3: es IDEMPOTENTE — llamarla de mas no estropea nada
-- =====================================================================================
do $$
declare
  v_uno int;
  v_tres int;
begin
  perform public.sync_follow_counters(array['bbbbbbbb-0808-4000-8000-00000000000b'::uuid]);
  select followers_count into v_uno
    from public.profiles where user_id = 'bbbbbbbb-0808-4000-8000-00000000000b';

  perform public.sync_follow_counters(array['bbbbbbbb-0808-4000-8000-00000000000b'::uuid]);
  perform public.sync_follow_counters(array['bbbbbbbb-0808-4000-8000-00000000000b'::uuid]);
  select followers_count into v_tres
    from public.profiles where user_id = 'bbbbbbbb-0808-4000-8000-00000000000b';

  assert v_uno = v_tres, 'Llamarla tres veces debe dar lo mismo que una; ' || v_uno || ' vs ' || v_tres;

  raise notice 'Caso 3 OK: idempotente';
end $$;

-- =====================================================================================
-- Caso 4: solo toca los usuarios que se le pasan
-- =====================================================================================
do $$
declare
  v_a int;
begin
  update public.profiles set following_count = 42
   where user_id = 'aaaaaaaa-0808-4000-8000-00000000000a';

  -- Se sincroniza SOLO B; A debe quedarse como estaba, aunque su numero sea falso.
  perform public.sync_follow_counters(array['bbbbbbbb-0808-4000-8000-00000000000b'::uuid]);

  select following_count into v_a
    from public.profiles where user_id = 'aaaaaaaa-0808-4000-8000-00000000000a';

  assert v_a = 42, 'No debe tocar a quien no se le pasa; A quedo en: ' || v_a;

  raise notice 'Caso 4 OK: acotada a los usuarios pedidos';
end $$;

-- =====================================================================================
-- Caso 5: no la puede ejecutar ni anon ni authenticated
-- =====================================================================================
-- En `public`, PostgREST la expondria como RPC. No falsearia nada (recalcula de la fuente de
-- verdad), pero seria trabajo de base de datos que dispara cualquiera, gratis.
do $$
declare
  v_anon boolean := false;
  v_auth boolean := false;
begin
  set local role anon;
  begin
    perform public.sync_follow_counters(array['bbbbbbbb-0808-4000-8000-00000000000b'::uuid]);
  exception when others then v_anon := true; end;
  reset role;

  set local role authenticated;
  begin
    perform public.sync_follow_counters(array['bbbbbbbb-0808-4000-8000-00000000000b'::uuid]);
  exception when others then v_auth := true; end;
  reset role;

  assert v_anon, 'anon no debe poder ejecutar sync_follow_counters';
  assert v_auth, 'authenticated no debe poder ejecutar sync_follow_counters';

  raise notice 'Caso 5 OK: solo service_role la ejecuta';
end $$;

rollback;
