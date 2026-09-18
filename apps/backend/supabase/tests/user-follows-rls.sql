-- Test de RLS de `user_follows` (Fase 4, Tarea 2).
--
-- Punto 5 de la skill `rls-security`: una policy no se da por buena leyendo el SQL, se prueba con
-- usuarios reales. Aquí hacen falta TRES: A, B y un tercero C, porque lo que hay que comprobar no
-- es "el dueño ve su fila" (eso lo prueban dos), sino que un ajeno NO ve una solicitud pendiente
-- que todavía no le concierne (RN-12) y SÍ la ve en cuanto pasa a aceptada.
--
-- CÓMO SE EJECUTA
--     docker exec -i supabase_db_backend psql -U postgres -d postgres \
--       -v ON_ERROR_STOP=1 -f - < apps/backend/supabase/tests/user-follows-rls.sql
--
-- Todo corre dentro de una transacción que termina en ROLLBACK: no deja rastro.
--
-- CÓMO SE SIMULA UN USUARIO CONCRETO (verificado contra esta base, no supuesto)
-- `auth.uid()` lee `current_setting('request.jwt.claim.sub', true)` o, si no está, la clave `sub`
-- de `request.jwt.claims`. `set local role authenticated` hace que además se apliquen los GRANT
-- de ese rol (y no los de `postgres`, que es superusuario y se salta RLS). Los dos ajustes son
-- `local`: no sobreviven al `rollback` ni se escapan del bloque de la transacción.

begin;

-- =====================================================================================
-- Caso 0: existen la tabla, su policy y los dos índices del plan
-- =====================================================================================
do $$
begin
  assert exists (
    select 1 from pg_policies
     where schemaname = 'public' and tablename = 'user_follows'
       and policyname = 'user_follows_read_own_or_accepted'
  ), 'Debe existir la policy user_follows_read_own_or_accepted';

  assert exists (
    select 1 from pg_indexes
     where schemaname = 'public' and tablename = 'user_follows'
       and indexname = 'user_follows_followee_status_idx'
  ), 'Debe existir el indice user_follows_followee_status_idx';

  assert exists (
    select 1 from pg_indexes
     where schemaname = 'public' and tablename = 'user_follows'
       and indexname = 'user_follows_follower_pending_created_at_idx'
  ), 'Debe existir el indice parcial user_follows_follower_pending_created_at_idx';

  raise notice 'Caso 0 OK: tabla, policy e indices presentes';
end $$;

-- =====================================================================================
-- Caso 1: preparación — A, B y C dados de alta por el único camino real (auth.users)
-- =====================================================================================
-- `display_name` va en la metadata porque `handle_new_user` lo exige desde el ADR 0018; sin él
-- el alta se rechaza y este fichero no probaría nada.
do $$
begin
  insert into auth.users (id, email, raw_user_meta_data)
  values
    ('aaaaaaaa-f011-0000-0000-000000000001', 'follows-a@example.test', '{"display_name":"Follows A"}'::jsonb),
    ('aaaaaaaa-f011-0000-0000-000000000002', 'follows-b@example.test', '{"display_name":"Follows B"}'::jsonb),
    ('aaaaaaaa-f011-0000-0000-000000000003', 'follows-c@example.test', '{"display_name":"Follows C"}'::jsonb);

  raise notice 'Caso 1 OK: A, B y C dados de alta';
end $$;

-- =====================================================================================
-- Caso 2: service_role inserta la solicitud pending A -> B, como haría `follow-toggle`
-- =====================================================================================
do $$
begin
  set local role service_role;
  insert into public.user_follows (follower_id, followee_id, status)
  values ('aaaaaaaa-f011-0000-0000-000000000001', 'aaaaaaaa-f011-0000-0000-000000000002', 'pending');
  reset role;

  assert exists (
    select 1 from public.user_follows
     where follower_id = 'aaaaaaaa-f011-0000-0000-000000000001'
       and followee_id = 'aaaaaaaa-f011-0000-0000-000000000002'
       and status = 'pending'
  ), 'La fila pending A->B debe existir (insertada como postgres tras el set local role)';

  raise notice 'Caso 2 OK: service_role puede insertar la solicitud pending';
end $$;

-- =====================================================================================
-- Caso 3: C (un tercero SIN relación con la fila) NO ve la solicitud pending
-- =====================================================================================
-- Este es el corazón de la divergencia con el documento maestro y con la tabla de referencia de
-- `rls-security`, que hoy dicen "pública": una solicitud pendiente no lo es.
do $$
declare
  v_filas int;
begin
  set local role authenticated;
  set local request.jwt.claims = '{"sub":"aaaaaaaa-f011-0000-0000-000000000003"}';

  select count(*) into v_filas
    from public.user_follows
   where follower_id = 'aaaaaaaa-f011-0000-0000-000000000001'
     and followee_id = 'aaaaaaaa-f011-0000-0000-000000000002';

  reset role;

  assert v_filas = 0,
    'C no debe ver la solicitud pending A->B; filas visibles: ' || v_filas;

  raise notice 'Caso 3 OK: C no ve la solicitud pending';
end $$;

-- =====================================================================================
-- Caso 4: A (el solicitante) y B (el destinatario) SÍ ven la solicitud pending
-- =====================================================================================
do $$
declare
  v_filas_a int;
  v_filas_b int;
begin
  set local role authenticated;
  set local request.jwt.claims = '{"sub":"aaaaaaaa-f011-0000-0000-000000000001"}';
  select count(*) into v_filas_a
    from public.user_follows
   where follower_id = 'aaaaaaaa-f011-0000-0000-000000000001'
     and followee_id = 'aaaaaaaa-f011-0000-0000-000000000002';
  reset role;

  set local role authenticated;
  set local request.jwt.claims = '{"sub":"aaaaaaaa-f011-0000-0000-000000000002"}';
  select count(*) into v_filas_b
    from public.user_follows
   where follower_id = 'aaaaaaaa-f011-0000-0000-000000000001'
     and followee_id = 'aaaaaaaa-f011-0000-0000-000000000002';
  reset role;

  assert v_filas_a = 1, 'A (el solicitante) debe ver su propia solicitud; vio: ' || v_filas_a;
  assert v_filas_b = 1, 'B (el destinatario) debe ver la solicitud recibida; vio: ' || v_filas_b;

  raise notice 'Caso 4 OK: A y B ven la solicitud pending, cada uno la suya';
end $$;

-- =====================================================================================
-- Caso 5: al aceptar (pending -> accepted), C SÍ pasa a ver la fila
-- =====================================================================================
do $$
declare
  v_filas int;
begin
  set local role service_role;
  update public.user_follows set status = 'accepted'
   where follower_id = 'aaaaaaaa-f011-0000-0000-000000000001'
     and followee_id = 'aaaaaaaa-f011-0000-0000-000000000002';
  reset role;

  set local role authenticated;
  set local request.jwt.claims = '{"sub":"aaaaaaaa-f011-0000-0000-000000000003"}';
  select count(*) into v_filas
    from public.user_follows
   where follower_id = 'aaaaaaaa-f011-0000-0000-000000000001'
     and followee_id = 'aaaaaaaa-f011-0000-0000-000000000002';
  reset role;

  assert v_filas = 1,
    'C debe ver la relacion en cuanto pasa a accepted; vio: ' || v_filas;

  raise notice 'Caso 5 OK: C ve la relacion accepted (deja de ser pending)';
end $$;

-- =====================================================================================
-- Caso 6: `authenticated` no puede escribir esta tabla por ningún camino (sin grant de escritura)
-- =====================================================================================
-- No hay policy de insert/update/delete y tampoco hay GRANT de esos verbos: las dos capas cierran
-- el mismo camino. Se espera 42501 (permission denied), no un rechazo de RLS.
do $$
declare
  v_sqlstate text;
begin
  begin
    set local role authenticated;
    set local request.jwt.claims = '{"sub":"aaaaaaaa-f011-0000-0000-000000000001"}';
    insert into public.user_follows (follower_id, followee_id, status)
    values ('aaaaaaaa-f011-0000-0000-000000000001', 'aaaaaaaa-f011-0000-0000-000000000003', 'pending');
    reset role;
    assert false, 'authenticated no deberia poder insertar en user_follows';
  exception when others then
    v_sqlstate := sqlstate;
    reset role;
  end;

  assert v_sqlstate = '42501',
    'El intento de insert de authenticated debe fallar con 42501 (permission denied), no con: '
    || v_sqlstate;

  raise notice 'Caso 6 OK: authenticated no puede insertar (permission denied, no RLS)';
end $$;

-- =====================================================================================
-- Caso 7: `anon` no tiene ningún grant sobre esta tabla
-- =====================================================================================
do $$
declare
  v_grants text;
begin
  select coalesce(string_agg(distinct grantee || ':' || privilege_type, ', '), '(ninguno)')
    into v_grants
    from information_schema.role_table_grants
   where table_schema = 'public' and table_name = 'user_follows' and grantee = 'anon';

  assert v_grants = '(ninguno)',
    'anon no debe tener ningun grant sobre user_follows; hay: ' || v_grants;

  raise notice 'Caso 7 OK: anon sin grants sobre user_follows';
end $$;

rollback;
