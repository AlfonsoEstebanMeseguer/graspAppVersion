-- Test de `rooms_feed` (Fase 5, Tarea 4).
--
-- El feed excluye las salas de quien has bloqueado y de quien te ha bloqueado. "No aparece" es una
-- afirmación sobre DOS respuestas, no sobre una: un conjunto vacío cumple cualquier igualdad, así
-- que junto a cada caso de bloqueo va un caso de control que afirma que la cuenta que NO bloquea
-- SÍ ve la sala, y que la ve por su id -- no solo que su feed no está vacío.
--
-- CÓMO SE EJECUTA
--     docker exec -i supabase_db_backend psql -U postgres -d postgres \
--       -v ON_ERROR_STOP=1 < apps/backend/supabase/tests/rooms-feed.sql
begin;

create extension if not exists pgtap;
select plan(8);

-- Semilla. `handle_new_user` exige `display_name` en `raw_user_meta_data` (ADR 0018, punto 4f de
-- db-schema) -- mismo motivo que en rooms-rls.sql / rooms-actions.sql.
insert into auth.users (id, email, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111', 'host@t.dev',   '{"display_name":"Hugo"}'::jsonb),
  ('22222222-2222-2222-2222-222222222222', 'bloq@t.dev',    '{"display_name":"Bea"}'::jsonb),
  ('33333333-3333-3333-3333-333333333333', 'ctrl@t.dev',    '{"display_name":"Carla"}'::jsonb),
  ('44444444-4444-4444-4444-444444444444', 'bloqueado@t.dev', '{"display_name":"Boris"}'::jsonb);

insert into public.categories (id, name, slug)
  values ('55555555-5555-5555-5555-555555555555', 'Ansiedad test', 'ansiedad-test');

-- La sala del host (Hugo). Ambas direcciones de bloqueo se prueban contra ESTA sala:
--   * Bea (n2) bloquea a Hugo -> Bea no ve la sala.
--   * Hugo bloquea a Boris (n4) -> Boris no ve la sala, aunque Boris no haya bloqueado a nadie.
-- Carla (n3) no bloquea ni está bloqueada por nadie: es el control de las dos direcciones.
insert into public.rooms (id, host_id, title, category_id, last_activity_at) values
  ('66666666-6666-6666-6666-666666666666',
   '11111111-1111-1111-1111-111111111111', 'Sala de Hugo',
   '55555555-5555-5555-5555-555555555555', now() - interval '10 minutes');

insert into public.blocks (blocker_id, blocked_id) values
  ('22222222-2222-2222-2222-222222222222', '11111111-1111-1111-1111-111111111111'), -- Bea bloquea a Hugo
  ('11111111-1111-1111-1111-111111111111', '44444444-4444-4444-4444-444444444444'); -- Hugo bloquea a Boris

-- Un oyente vivo en la sala de Hugo, para el caso de `participants` de más abajo.
insert into public.room_participants (room_id, user_id, role) values
  ('66666666-6666-6666-6666-666666666666',
   '33333333-3333-3333-3333-333333333333', 'listener');

-- Caso 1 (control): Carla no bloquea a nadie ni está bloqueada -- SÍ ve la sala de Hugo.
set local role authenticated;
set local request.jwt.claims = '{"sub":"33333333-3333-3333-3333-333333333333"}';
select ok(
  (select count(*)::int from rooms_feed(null)) > 0,
  'caso 1 (control): sin bloqueo, el feed NO está vacío'
);
select ok(
  exists(select 1 from rooms_feed(null) where id = '66666666-6666-6666-6666-666666666666'),
  'caso 1 (control): y la sala de Hugo SÍ está en él'
);
-- `participants` viaja EMPAQUETADO en el propio RPC (ver comentario en la migración): no hace
-- falta una segunda consulta contra `room_participants` filtrando `left_at`, columna que
-- `authenticated` no tiene concedida. Se comprueba que trae a Carla, la única oyente viva.
select ok(
  (select participants from rooms_feed(null)
     where id = '66666666-6666-6666-6666-666666666666')
    @> jsonb_build_array(jsonb_build_object(
         'userId', '33333333-3333-3333-3333-333333333333', 'role', 'listener')),
  'caso 1 (control): participants trae a la oyente viva de la sala'
);

-- Caso 2: Bea bloqueó a Hugo (yo bloqueé al host) -- su sala no aparece.
reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"22222222-2222-2222-2222-222222222222"}';
select is(
  (select count(*)::int from rooms_feed(null)
     where id = '66666666-6666-6666-6666-666666666666'),
  0,
  'caso 2: la sala de un host al que he bloqueado no aparece'
);

-- Caso 3: Hugo bloqueó a Boris (el host me bloqueó a mí) -- la dirección recíproca, la que
-- `security invoker` sobre `blocks` (RLS `blocks_read_own`, solo `blocker_id = auth.uid()`) NO
-- podría ver, porque la fila la escribió Hugo, no Boris. Por eso el RPC es `security definer`.
reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"44444444-4444-4444-4444-444444444444"}';
select is(
  (select count(*)::int from rooms_feed(null)
     where id = '66666666-6666-6666-6666-666666666666'),
  0,
  'caso 3: la sala de un host que me ha bloqueado a mí tampoco aparece'
);

-- Caso 4: el orden es por actividad reciente. Segunda sala de otro host, más reciente que la de
-- Hugo -- tiene que salir primero para Carla, que no tiene ningún bloqueo de por medio.
reset role;
insert into auth.users (id, email, raw_user_meta_data)
  values ('77777777-7777-7777-7777-777777777777', 'host2@t.dev', '{"display_name":"Hilda"}'::jsonb);
insert into public.rooms (id, host_id, title, category_id, last_activity_at) values
  ('88888888-8888-8888-8888-888888888888',
   '77777777-7777-7777-7777-777777777777', 'Sala de Hilda',
   '55555555-5555-5555-5555-555555555555', now());

-- Sin `order by` en esta consulta exterior a propósito: el orden que se prueba es el que aplica
-- `rooms_feed` por dentro. Si se reordenara aquí otra vez, invertir el `order by` del RPC no
-- tumbaría este caso -- se comprobó a mano, y es justo la mutación que pide el encargo.
set local role authenticated;
set local request.jwt.claims = '{"sub":"33333333-3333-3333-3333-333333333333"}';
select is(
  (select id from rooms_feed(null) limit 1),
  '88888888-8888-8888-8888-888888888888',
  'caso 4: arriba sale la de actividad más reciente (Hilda, no Hugo)'
);

-- Caso 5: el filtro por categoría es opcional pero, si se pasa, sí filtra -- categoría que ninguna
-- sala tiene da cero resultados.
reset role;
insert into public.categories (id, name, slug)
  values ('99999999-9999-9999-9999-999999999999', 'Otra test', 'otra-test');
set local role authenticated;
set local request.jwt.claims = '{"sub":"33333333-3333-3333-3333-333333333333"}';
select is(
  (select count(*)::int
     from rooms_feed('99999999-9999-9999-9999-999999999999'::uuid)),
  0,
  'caso 5: filtrar por una categoría sin salas da un feed vacío'
);

-- Caso 6: `authenticated` puede llamar al RPC de verdad (no solo como `postgres`, el dueño, que
-- nunca necesita el grant -- punto 2 de la lección de la Tarea 3). Si esto fallara, los seis casos
-- de arriba no probarían nada real sobre el grant que usa `rooms-feed/index.ts`.
select is(
  (select count(*)::int
     from information_schema.routine_privileges
    where routine_name = 'rooms_feed' and grantee = 'authenticated'
      and privilege_type = 'EXECUTE'),
  1,
  'caso 6: authenticated tiene EXECUTE sobre rooms_feed, comprobado en information_schema'
);

select * from finish();
rollback;
