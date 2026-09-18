-- Test de RLS y grants de las salas (Fase 5, Tarea 1).
--
-- CÓMO SE EJECUTA
--     docker exec -i supabase_db_backend psql -U postgres -d postgres \
--       -v ON_ERROR_STOP=1 < apps/backend/supabase/tests/rooms-rls.sql
begin;

create extension if not exists pgtap;
select plan(21);

-- Semilla
-- `handle_new_user` exige `display_name` en `raw_user_meta_data` (ADR 0018, punto 4f de
-- db-schema): sin él el alta revienta con `display_name es obligatorio` antes de llegar a
-- ninguna de las tablas de esta tarea.
insert into auth.users (id, email, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111', 'host@t.dev',
   '{"display_name":"Hugo"}'::jsonb),
  ('22222222-2222-2222-2222-222222222222', 'oyente@t.dev',
   '{"display_name":"Olga"}'::jsonb);
insert into public.categories (id, name, slug)
  values ('33333333-3333-3333-3333-333333333333', 'Ansiedad', 'ansiedad');
insert into public.rooms (id, host_id, title, category_id) values
  ('44444444-4444-4444-4444-444444444444',
   '11111111-1111-1111-1111-111111111111', 'Hablemos de ansiedad',
   '33333333-3333-3333-3333-333333333333');

-- Caso 1: authenticated ve las salas live
set local role authenticated;
set local request.jwt.claims = '{"sub":"22222222-2222-2222-2222-222222222222"}';
select is(
  (select count(*)::int from public.rooms),
  1,
  'caso 1: un autenticado ve la sala live'
);

-- Caso 2: authenticated NO ve las salas ended
reset role;
update public.rooms set status = 'ended', ended_at = now(),
  ended_reason = 'host_ended'
  where id = '44444444-4444-4444-4444-444444444444';
set local role authenticated;
set local request.jwt.claims = '{"sub":"22222222-2222-2222-2222-222222222222"}';
select is(
  (select count(*)::int from public.rooms),
  0,
  'caso 2: una sala ended no se ve'
);
reset role;
update public.rooms set status = 'live', ended_at = null, ended_reason = null
  where id = '44444444-4444-4444-4444-444444444444';

-- Caso 3: authenticated NO puede insertar una sala directamente
set local role authenticated;
set local request.jwt.claims = '{"sub":"22222222-2222-2222-2222-222222222222"}';
select throws_ok(
  $$insert into public.rooms (host_id, title, category_id)
    values ('22222222-2222-2222-2222-222222222222', 'mia',
            '33333333-3333-3333-3333-333333333333')$$,
  '42501',
  null,
  'caso 3: crear una sala a pelo esta prohibido'
);

-- Caso 4: authenticated NO puede cerrarla
select throws_ok(
  $$update public.rooms set status = 'ended'$$,
  '42501',
  null,
  'caso 4: cerrar una sala a pelo esta prohibido'
);

-- Caso 5: los grants de rooms para authenticated son SOLO los siete de lectura
reset role;
select is(
  (select count(*)::int
     from information_schema.column_privileges
    where table_name = 'rooms' and grantee = 'authenticated'
      and privilege_type = 'SELECT'),
  7,
  'caso 5: authenticated lee 7 columnas de rooms, ni una mas'
);

-- Caso 6: ended_reason NO esta entre ellas
select is(
  (select count(*)::int
     from information_schema.column_privileges
    where table_name = 'rooms' and grantee = 'authenticated'
      and column_name in ('ended_reason', 'ended_at')),
  0,
  'caso 6: ended_reason y ended_at no se conceden'
);

-- Caso 7: anon no tiene ni un grant sobre las tres tablas
select is(
  (select count(*)::int
     from information_schema.column_privileges
    where table_name in ('rooms', 'room_participants', 'room_messages')
      and grantee = 'anon'),
  0,
  'caso 7: anon no tiene ningun grant'
);

-- Caso 8: una persona no puede tener dos salas live
reset role;
select throws_ok(
  $$insert into public.rooms (host_id, title, category_id)
    values ('11111111-1111-1111-1111-111111111111', 'otra',
            '33333333-3333-3333-3333-333333333333')$$,
  '23505',
  null,
  'caso 8: un host no puede tener dos salas live a la vez'
);

-- Caso 9: un titulo de 2 caracteres no pasa el check
select throws_ok(
  $$insert into public.rooms (host_id, title, category_id)
    values ('22222222-2222-2222-2222-222222222222', 'ab',
            '33333333-3333-3333-3333-333333333333')$$,
  '23514',
  null,
  'caso 9: el titulo exige al menos 3 caracteres'
);

-- ==================================================================================
-- Tarea 6: el borrado de cuenta no deja salas fantasma.
--
-- El plan del brief proponia llamar a `room_leave` desde `account-delete` antes de
-- borrar. Comprobado contra base real (los tres FK de la migracion 20260901120000):
--   rooms.host_id             -> auth.users on delete cascade
--   room_participants.room_id -> rooms(id)  on delete cascade
--   room_participants.user_id -> auth.users on delete cascade
--   room_messages.room_id     -> rooms(id)  on delete cascade
--   room_messages.sender_id   -> auth.users on delete cascade
-- Borrar al host dispara un DELETE en cascada de tres niveles (auth.users -> rooms ->
-- room_participants/room_messages), NO un UPDATE de `status`. El trigger de la Tarea 5
-- (`room_messages_purge_on_end_trg`) nunca se dispara por esta via -- pero no hace
-- falta: el `on delete cascade` de `room_messages.room_id` se lleva los mensajes por
-- su cuenta, sin pasar por el trigger. Verificado tambien contra el camino real
-- (`account-delete` de verdad, con `room-actions` creando la sala y uniendo a un
-- segundo usuario): la sala, sus participantes y sus mensajes desaparecen enteros, y
-- quien seguia dentro queda libre para unirse a otra sala. Por eso NO se toca
-- `account-delete/index.ts`: anadir el `room_leave` del brief no haria nada que la
-- cascada no haga ya, y anadir codigo que no hace nada es el propio error que el
-- encargo pide evitar.
--
-- Lo que SI hace falta es este test, porque una cascada que hoy funciona la puede
-- romper una migracion futura sin que nadie se entere (p.ej. si alguien cambia
-- `room_participants.room_id` a `on delete restrict` para "proteger" el historial).

-- Seed: la sala '44444444...' (Hugo, host) con Hugo dentro como host y Olga como
-- oyente, mas un mensaje de Olga -- para que borrar a Hugo tenga algo real que
-- arrastrar en las tres tablas.
reset role;
insert into public.room_participants (room_id, user_id, role) values
  ('44444444-4444-4444-4444-444444444444',
   '11111111-1111-1111-1111-111111111111', 'host'),
  ('44444444-4444-4444-4444-444444444444',
   '22222222-2222-2222-2222-222222222222', 'listener');
insert into public.room_messages (room_id, sender_id, body) values
  ('44444444-4444-4444-4444-444444444444',
   '22222222-2222-2222-2222-222222222222', 'hola');

-- Caso 10: borrar al host se lleva la sala entera -- no queda live ni de ninguna
-- otra forma huerfana.
delete from auth.users where id = '11111111-1111-1111-1111-111111111111';
select is(
  (select count(*)::int from public.rooms
    where id = '44444444-4444-4444-4444-444444444444'),
  0,
  'caso 10: borrar al host no deja la sala huerfana (ni live ni ended)'
);

-- Caso 11: no quedan participantes -- ni Hugo ni Olga -- apuntando a una sala que
-- ya no existe. Es la mitad que de verdad importa (RN de la tarea): si quedara una
-- fila viva con left_at is null, esa persona no podria unirse a NINGUNA sala nunca
-- mas por `room_participants_one_room_idx`.
select is(
  (select count(*)::int from public.room_participants
    where room_id = '44444444-4444-4444-4444-444444444444'),
  0,
  'caso 11: no quedan participantes apuntando a la sala borrada'
);

-- Caso 12: los mensajes tambien se van, aunque el trigger de la Tarea 5 (que solo
-- escucha UPDATE ... status = 'ended') nunca se dispara en un DELETE en cascada.
select is(
  (select count(*)::int from public.room_messages
    where room_id = '44444444-4444-4444-4444-444444444444'),
  0,
  'caso 12: los mensajes de la sala borrada tambien desaparecen'
);

-- Caso 13: Olga -- que estaba dentro cuando se borro a Hugo -- puede volver a
-- unirse a otra sala. Si quedara una fila huerfana con left_at is null, este
-- insert reventaria contra el indice unico parcial.
insert into public.rooms (id, host_id, title, category_id) values
  ('55555555-5555-5555-5555-555555555555',
   '22222222-2222-2222-2222-222222222222', 'Sala nueva de Olga',
   '33333333-3333-3333-3333-333333333333');
select lives_ok(
  $$insert into public.room_participants (room_id, user_id, role)
    values ('55555555-5555-5555-5555-555555555555',
            '22222222-2222-2222-2222-222222222222', 'host')$$,
  'caso 13: Olga puede reentrar en una sala nueva tras el borrado del host'
);

-- Caso 14 y 14b: si quien se borra NO es el host sino alguien que esta dentro, la
-- sala sigue viva y el aforo se recalcula solo -- la fila del borrado desaparece
-- por la cascada de auth.users, no por ningun codigo de room-actions.
insert into auth.users (id, email, raw_user_meta_data) values
  ('66666666-6666-6666-6666-666666666666', 'otto@t.dev',
   '{"display_name":"Otto"}'::jsonb);
insert into public.room_participants (room_id, user_id, role) values
  ('55555555-5555-5555-5555-555555555555',
   '66666666-6666-6666-6666-666666666666', 'listener');
delete from auth.users where id = '66666666-6666-6666-6666-666666666666';
select is(
  (select status from public.rooms
    where id = '55555555-5555-5555-5555-555555555555'),
  'live',
  'caso 14: borrar a alguien que no es el host no cierra su sala'
);
select is(
  (select count(*)::int from public.room_participants
    where room_id = '55555555-5555-5555-5555-555555555555'
      and left_at is null),
  1,
  'caso 14b: el aforo baja solo -- ni fila viva ni huerfana de quien se borro'
);

-- ==================================================================================
-- Vuelta de arreglos 1: `room_messages` funciona con un JWT normal, no solo con
-- `postgres`.
--
-- Las dos policies de `room_messages` filtran por `room_participants.left_at`, y esa
-- columna NUNCA se le concede a `authenticated` (a proposito, ver el comentario de
-- `rooms_feed` en 20260901120000_rooms.sql). Una policy se evalua con los permisos de
-- quien consulta -- asi que un JWT de usuario normal no podia ni leer ni insertar en
-- `room_messages`, y ningun caso de este fichero lo detecto porque TODO corre como
-- `postgres` salvo los casos 1, 3, 4 y 8-9, que nunca tocan `room_messages`. Se cierra
-- con `public.is_room_member(uuid)` -- `security definer`, mismo patron que
-- `rooms_feed` -- que las dos policies llaman en vez de exponer `left_at`
-- (20260901140000_room_messages_membership_fn.sql).
--
-- Los tres casos que importan: alguien vivo dentro puede; alguien que nunca estuvo no
-- puede; y alguien que ESTUVO pero se fue (`left_at` puesto) tampoco -- este ultimo es
-- el que da sentido a la comprobacion entera: si la policy ignorara `left_at`, el
-- caso 21 devolveria 1, no 0.
reset role;
insert into auth.users (id, email, raw_user_meta_data) values
  ('88888888-8888-8888-8888-888888888881', 'forastero@t.dev',
   '{"display_name":"Fausto"}'::jsonb),
  ('88888888-8888-8888-8888-888888888882', 'exmiembro@t.dev',
   '{"display_name":"Exme"}'::jsonb);

-- exmiembro entra y se va de la sala de Olga (555...5, viva desde el caso 13) para
-- dejar una fila con `left_at` puesto -- justo lo que no se debe poder usar.
insert into public.room_participants (room_id, user_id, role, left_at) values
  ('55555555-5555-5555-5555-555555555555',
   '88888888-8888-8888-8888-888888888882', 'listener', now());

-- Caso 16: Olga -- viva dentro de su propia sala -- puede insertar un mensaje con su
-- propio JWT, no con `service_role` ni `postgres`.
set local role authenticated;
set local request.jwt.claims = '{"sub":"22222222-2222-2222-2222-222222222222"}';
select lives_ok(
  $$insert into public.room_messages (room_id, sender_id, body)
    values ('55555555-5555-5555-5555-555555555555',
            '22222222-2222-2222-2222-222222222222', 'hola desde Olga')$$,
  'caso 16: un participante vivo puede insertar un mensaje en su sala'
);

-- Caso 17: y puede leerlo.
select is(
  (select count(*)::int from public.room_messages
    where room_id = '55555555-5555-5555-5555-555555555555'),
  1,
  'caso 17: un participante vivo lee los mensajes de su sala'
);

-- Caso 18: Fausto -- nunca estuvo en la sala -- no puede insertar.
reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"88888888-8888-8888-8888-888888888881"}';
select throws_ok(
  $$insert into public.room_messages (room_id, sender_id, body)
    values ('55555555-5555-5555-5555-555555555555',
            '88888888-8888-8888-8888-888888888881', 'colandome')$$,
  '42501',
  null,
  'caso 18: quien no esta en la sala no puede insertar un mensaje'
);

-- Caso 19: ...ni leer -- RLS filtra filas, no lanza error: la consulta devuelve 0.
select is(
  (select count(*)::int from public.room_messages
    where room_id = '55555555-5555-5555-5555-555555555555'),
  0,
  'caso 19: quien no esta en la sala no ve sus mensajes'
);

-- Caso 20: Exme -- estuvo, pero se fue (`left_at` puesto) -- tampoco puede insertar.
reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"88888888-8888-8888-8888-888888888882"}';
select throws_ok(
  $$insert into public.room_messages (room_id, sender_id, body)
    values ('55555555-5555-5555-5555-555555555555',
            '88888888-8888-8888-8888-888888888882', 'ya me fui')$$,
  '42501',
  null,
  'caso 20: quien se fue de la sala (left_at puesto) no puede insertar'
);

-- Caso 21: ...ni leer -- el caso que de verdad prueba que `is_room_member` mira
-- `left_at`. Si la policy lo ignorara, este select devolveria 1 (el mensaje de Olga
-- del caso 16), no 0.
select is(
  (select count(*)::int from public.room_messages
    where room_id = '55555555-5555-5555-5555-555555555555'),
  0,
  'caso 21: quien se fue de la sala no ve sus mensajes'
);

select * from finish();
rollback;
