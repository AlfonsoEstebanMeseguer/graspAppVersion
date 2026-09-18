-- Salas de voz (Fase 5). Sin audio: eso es la Fase 6.
-- Spec: docs/superpowers/specs/2026-08-31-salas-de-voz-fase5-design.md
-- Decision del feed: docs/decisions/0032-el-feed-de-salas-no-se-personaliza.md

create table if not exists public.rooms (
  id uuid primary key default gen_random_uuid(),
  host_id uuid not null references auth.users(id) on delete cascade,
  title text not null check (char_length(btrim(title)) between 3 and 80),
  -- restrict, NO cascade: borrar una categoria no puede llevarse por delante
  -- conversaciones vivas. categories.parent_id si usa cascade; aqui no aplica.
  category_id uuid not null references public.categories(id) on delete restrict,
  status text not null default 'live' check (status in ('live', 'ended')),
  created_at timestamptz not null default now(),
  -- Dos lectores reales, que es lo que justifica que exista: el orden del feed
  -- (ADR 0032) y el cron que cierra por inactividad.
  last_activity_at timestamptz not null default now(),
  ended_at timestamptz,
  ended_reason text check (ended_reason in
    ('host_left', 'expired', 'empty', 'idle', 'host_ended'))
);

create index if not exists rooms_live_activity_idx
  on public.rooms (last_activity_at desc) where status = 'live';
create index if not exists rooms_live_category_idx
  on public.rooms (category_id, last_activity_at desc) where status = 'live';
create unique index if not exists rooms_one_live_per_host_idx
  on public.rooms (host_id) where status = 'live';

create table if not exists public.room_participants (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.rooms(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'listener'
    check (role in ('host', 'speaker', 'listener')),
  joined_at timestamptz not null default now(),
  left_at timestamptz,
  hand_raised_at timestamptz,
  -- La frase de la peticion de turno. Sale del boceto 04-room-active.jpeg.
  hand_raised_note text check (hand_raised_note is null
    or char_length(btrim(hand_raised_note)) between 1 and 120)
);

create index if not exists room_participants_alive_idx
  on public.room_participants (room_id) where left_at is null;
create unique index if not exists room_participants_one_room_idx
  on public.room_participants (user_id) where left_at is null;
-- Pide la spec (S4.2): permite re-entrar tras salir. Sin este indice, room-actions
-- (Tarea 3) no puede resolver el re-ingreso con un `on conflict` -- cada salida crea
-- una fila nueva con el mismo (room_id, user_id) pero otro `joined_at`, y este es el
-- indice contra el que ese `on conflict` necesita apuntar.
create unique index if not exists room_participants_room_user_joined_idx
  on public.room_participants (room_id, user_id, joined_at);

create table if not exists public.room_messages (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.rooms(id) on delete cascade,
  sender_id uuid not null references auth.users(id) on delete cascade,
  body text not null check (char_length(btrim(body)) between 1 and 500),
  created_at timestamptz not null default now()
);

create index if not exists room_messages_room_idx
  on public.room_messages (room_id, created_at);

alter table public.rooms enable row level security;
alter table public.room_participants enable row level security;
alter table public.room_messages enable row level security;

-- Nace sin permisos y esta migracion concede lo justo.
revoke all on public.rooms from authenticated, anon;
revoke all on public.room_participants from authenticated, anon;
revoke all on public.room_messages from authenticated, anon;

-- RLS filtra filas; el GRANT filtra columnas. Se enumeran: ended_reason y
-- ended_at no los pinta nadie, asi que no se conceden.
grant select (id, host_id, title, category_id, status, created_at,
              last_activity_at) on public.rooms to authenticated;
grant select (id, room_id, user_id, role, joined_at, hand_raised_at,
              hand_raised_note) on public.room_participants to authenticated;
grant select (id, room_id, sender_id, body, created_at)
  on public.room_messages to authenticated;
grant insert (room_id, sender_id, body) on public.room_messages to authenticated;

drop policy if exists "rooms_read_live" on public.rooms;
create policy "rooms_read_live" on public.rooms
  for select to authenticated using (status = 'live');

drop policy if exists "room_participants_read_live" on public.room_participants;
create policy "room_participants_read_live" on public.room_participants
  for select to authenticated using (
    exists (select 1 from public.rooms r
             where r.id = room_id and r.status = 'live')
  );

drop policy if exists "room_messages_read_own_room" on public.room_messages;
create policy "room_messages_read_own_room" on public.room_messages
  for select to authenticated using (
    exists (select 1 from public.room_participants p
             where p.room_id = room_messages.room_id
               and p.user_id = auth.uid() and p.left_at is null)
  );

drop policy if exists "room_messages_insert_own" on public.room_messages;
create policy "room_messages_insert_own" on public.room_messages
  for insert to authenticated with check (
    sender_id = auth.uid()
    and exists (select 1 from public.room_participants p
                 where p.room_id = room_messages.room_id
                   and p.user_id = auth.uid() and p.left_at is null)
  );

-- Sin policies de escritura sobre rooms ni room_participants: eso es
-- room-actions con service_role, que se salta RLS pero NO los grants.

-- service_role: BYPASSRLS, NO BYPASSGRANT (punto 12 de rls-security). El default ACL de `public`
-- para relaciones creadas por `postgres` NO le da a service_role select/insert/update (solo
-- delete/references/trigger/maintain) -- se comprueba con pg_default_acl, no se asume. Sin este
-- grant explicito, `room-actions` (Tarea 3) devolveria "permission denied" en cualquier entorno
-- nuevo. Mismo patron que `20260823120200_messaging.sql`.
grant select, insert, update, delete on public.rooms              to service_role;
grant select, insert, update, delete on public.room_participants  to service_role;
grant select, insert, update, delete on public.room_messages      to service_role;

-- Topes de aforo. S3.4 de la spec (enmendada 2026-08-31): la autoridad es Postgres, no
-- `_shared/rooms.ts`, porque el aforo se tiene que comprobar DENTRO de la transaccion
-- que escribe (S5.1, `room-actions`, Tarea 3). `_shared/rooms.ts` conserva las mismas
-- constantes solo para pintar limites en el cliente, como espejo declarado; si un dia
-- divergen, esta es la version que manda.
create or replace function public.room_max_occupants() returns int
  language sql immutable
  set search_path = ''
  as $$ select 20 $$;

create or replace function public.room_max_speakers() returns int
  language sql immutable
  set search_path = ''
  as $$ select 2 $$;

-- Son funciones puras sin SECURITY DEFINER, pero PostgREST las expone igual como RPC
-- (`POST /rest/v1/rpc/room_max_occupants`) salvo que se revoque EXECUTE (punto 11 de db-schema).
-- Se llaman desde SQL (triggers/funciones de la Tarea 3), no desde el cliente.
revoke execute on function public.room_max_occupants() from public, anon, authenticated;
revoke execute on function public.room_max_speakers() from public, anon, authenticated;

-- El `revoke ... from public` de arriba tambien le retira a `service_role` el EXECUTE que
-- tenia por ser miembro implicito de PUBLIC: BYPASSRLS no es BYPASSGRANT (punto 12 de
-- rls-security), y aqui aplica por el lado de EXECUTE igual que aplico por el lado de los
-- grants de tabla. Sin este grant explicito, `room-actions` (Tarea 3) revienta con
-- "permission denied for function" en cualquier entorno nuevo.
grant execute on function public.room_max_occupants() to service_role;
grant execute on function public.room_max_speakers()  to service_role;

-- Funciones de escritura de room-actions (Tarea 3). Las reglas de negocio
-- (aforo, tope de hablantes, quien es el host) se cuentan DENTRO de la misma
-- transaccion que escribe -- por eso el `for update` sobre la fila de `rooms`:
-- serializa a quienes compiten por el mismo hueco, y contar fuera de la
-- transaccion dejaria pasar a dos peticiones simultaneas cuando solo queda
-- una plaza. Los topes se leen de `room_max_occupants()`/`room_max_speakers()`,
-- nunca como literal: esa es la autoridad declarada mas arriba en esta misma
-- migracion.
create or replace function public.room_create(
  p_host uuid, p_title text, p_category uuid
) returns uuid language plpgsql security definer set search_path = public as $$
declare v_room uuid;
begin
  if exists (select 1 from room_participants
              where user_id = p_host and left_at is null) then
    raise exception 'already_in_room' using errcode = 'P0001';
  end if;
  insert into rooms (host_id, title, category_id)
    values (p_host, p_title, p_category) returning id into v_room;
  insert into room_participants (room_id, user_id, role)
    values (v_room, p_host, 'host');
  return v_room;
end $$;

create or replace function public.room_join(p_user uuid, p_room uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  -- El lock serializa a los que entran a la vez: contar fuera y escribir
  -- despues deja pasar a dos a la vez cuando queda un hueco.
  perform 1 from rooms where id = p_room and status = 'live' for update;
  if not found then
    raise exception 'room_not_live' using errcode = 'P0001';
  end if;
  -- Sin esto, reunirse dos veces (doble toque, reintento de red) revienta con el
  -- 23505 crudo de `room_participants_one_room_idx` en vez de un error legible:
  -- se comprueba aqui, ANTES del insert, igual que ya hace `room_create` para el
  -- host. El indice es un unico PARCIAL (`where left_at is null`), no una PK
  -- compuesta -- por eso el chequeo es por `user_id` solo, no por `(room_id,
  -- user_id)`: nadie puede estar vivo en dos salas a la vez, ni dos veces en la
  -- misma.
  if exists (select 1 from room_participants
              where user_id = p_user and left_at is null) then
    raise exception 'already_in_room' using errcode = 'P0001';
  end if;
  if (select count(*) from room_participants
       where room_id = p_room and left_at is null) >= room_max_occupants() then
    raise exception 'room_full' using errcode = 'P0001';
  end if;
  insert into room_participants (room_id, user_id) values (p_room, p_user);
  update rooms set last_activity_at = now() where id = p_room;
end $$;

create or replace function public.room_raise_hand(
  p_user uuid, p_room uuid, p_note text
) returns void language plpgsql security definer set search_path = public as $$
begin
  update room_participants
     set hand_raised_at = now(), hand_raised_note = p_note
   where room_id = p_room and user_id = p_user
     and left_at is null and role = 'listener';
  if not found then
    raise exception 'not_a_listener' using errcode = 'P0001';
  end if;
end $$;

create or replace function public.room_grant_speak(
  p_host uuid, p_room uuid, p_target uuid
) returns void language plpgsql security definer set search_path = public as $$
begin
  perform 1 from rooms
   where id = p_room and host_id = p_host and status = 'live' for update;
  if not found then
    raise exception 'not_the_host' using errcode = 'P0001';
  end if;
  if (select count(*) from room_participants
       where room_id = p_room and left_at is null
         and role in ('host', 'speaker')) >= room_max_speakers() then
    raise exception 'stage_full' using errcode = 'P0001';
  end if;
  update room_participants
     set role = 'speaker', hand_raised_at = null, hand_raised_note = null
   where room_id = p_room and user_id = p_target
     and left_at is null and hand_raised_at is not null;
  if not found then
    raise exception 'no_request' using errcode = 'P0001';
  end if;
  update rooms set last_activity_at = now() where id = p_room;
end $$;

-- Bajar del escenario nunca puede estar lleno: no comprueba ningun tope, solo
-- que quien llama es el host de una sala live. Mismo patron de lock que
-- room_grant_speak, para serializar contra una concesion simultanea sobre el
-- mismo destinatario.
create or replace function public.room_revoke_speak(
  p_host uuid, p_room uuid, p_target uuid
) returns void language plpgsql security definer set search_path = public as $$
begin
  perform 1 from rooms
   where id = p_room and host_id = p_host and status = 'live' for update;
  if not found then
    raise exception 'not_the_host' using errcode = 'P0001';
  end if;
  update room_participants
     set role = 'listener'
   where room_id = p_room and user_id = p_target
     and left_at is null and role = 'speaker';
  if not found then
    raise exception 'not_a_speaker' using errcode = 'P0001';
  end if;
  update rooms set last_activity_at = now() where id = p_room;
end $$;

create or replace function public.room_leave(p_user uuid, p_room uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  update room_participants set left_at = now()
   where room_id = p_room and user_id = p_user and left_at is null;
  -- Si se va el host, la sala se acaba. Decision del 2026-08-31.
  if exists (select 1 from rooms
              where id = p_room and host_id = p_user and status = 'live') then
    update rooms set status = 'ended', ended_at = now(),
                     ended_reason = 'host_left' where id = p_room;
    update room_participants set left_at = now()
     where room_id = p_room and left_at is null;
  end if;
end $$;

-- `end` no es un alias de `leave`: un participante cualquiera puede *irse*, pero
-- solo el host puede *terminar* la sala para todos. Antes las dos accion es de
-- room-actions resolvian a room_leave, asi que cualquiera podia "acabar" una sala
-- ajena limitandose a salir de ella (y sin acabarla de verdad), y `ended_reason
-- = 'host_ended'` -- que SI esta en el check del esquema -- no lo escribia
-- ningun camino. Mismo patron de lock que room_grant_speak/room_revoke_speak.
create or replace function public.room_end(p_host uuid, p_room uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform 1 from rooms
   where id = p_room and host_id = p_host and status = 'live' for update;
  if not found then
    raise exception 'not_the_host' using errcode = 'P0001';
  end if;
  update rooms set status = 'ended', ended_at = now(),
                   ended_reason = 'host_ended' where id = p_room;
  update room_participants set left_at = now()
   where room_id = p_room and left_at is null;
end $$;

revoke all on function public.room_create(uuid, text, uuid) from public, anon, authenticated;
revoke all on function public.room_join(uuid, uuid) from public, anon, authenticated;
revoke all on function public.room_raise_hand(uuid, uuid, text) from public, anon, authenticated;
revoke all on function public.room_grant_speak(uuid, uuid, uuid) from public, anon, authenticated;
revoke all on function public.room_revoke_speak(uuid, uuid, uuid) from public, anon, authenticated;
revoke all on function public.room_leave(uuid, uuid) from public, anon, authenticated;
revoke all on function public.room_end(uuid, uuid) from public, anon, authenticated;

-- [Critical, vuelta de arreglos 1] Un `revoke all ... from public, anon, authenticated`
-- tambien le retira a `service_role` el EXECUTE que tenia por ser miembro implicito
-- de PUBLIC -- BYPASSRLS no es BYPASSGRANT (punto 12 de rls-security). Esto ya estaba
-- documentado y arreglado TREINTA LINEAS MAS ARRIBA para `room_max_occupants()` /
-- `room_max_speakers()`, y el mismo bug se colo sin arreglar en las siete funciones de
-- escritura: `room-actions` llama con `getServiceRoleClient()`, asi que sin este grant
-- explicito CUALQUIER accion de room-actions devuelve "permission denied for
-- function" en cualquier entorno nuevo. Ningun test que corra como `postgres` (el
-- dueno, que nunca necesita el grant) puede detectar este bug -- por eso el caso de
-- rooms-actions.sql que lo guarda cambia de rol con `set local role service_role`.
grant execute on function public.room_create(uuid, text, uuid)       to service_role;
grant execute on function public.room_join(uuid, uuid)                to service_role;
grant execute on function public.room_raise_hand(uuid, uuid, text)    to service_role;
grant execute on function public.room_grant_speak(uuid, uuid, uuid)   to service_role;
grant execute on function public.room_revoke_speak(uuid, uuid, uuid)  to service_role;
grant execute on function public.room_leave(uuid, uuid)               to service_role;
grant execute on function public.room_end(uuid, uuid)                 to service_role;

-- =================================================================================================
-- rooms-feed (Fase 5, Tarea 4) — la lista de salas activas (ADR 0032, `docs/decisions/0032-el-feed-de-salas-no-se-personaliza.md`).
--
-- SECURITY DEFINER, NO INVOKER, y es una decisión deliberada, no un descuido: `blocks_read_own`
-- (20260823120500_moderation.sql, RN-23) solo deja ver a `authenticated` las filas donde
-- `blocker_id = auth.uid()` -- ES la regla que impide que el bloqueado sepa que le han bloqueado.
-- Si esta función corriera `security invoker`, la mitad "el host me bloqueó a mí" (blocker_id =
-- host, blocked_id = yo) sería invisible para mi propia consulta bajo RLS, y la sala de quien me
-- bloqueó seguiría saliendo en mi feed -- justo la mitad que este test cubre a propósito. Como
-- `security definer` (dueño postgres, que no tiene la RLS de `blocks` activa por ser el dueño de la
-- tabla) se ven las dos filas sin abrir nada a nadie más: el filtro sigue siendo por `auth.uid()`,
-- que resuelve del JWT vía GUC de sesión y es independiente del contexto de seguridad de la función
-- (mismo motivo por el que `activity_status`, llamado con el cliente del usuario en `connect-feed`,
-- resuelve bien quién pregunta).
--
-- Se llama con el cliente del USUARIO, nunca con `service_role` (ver `requireAuthUser` en
-- `rooms-feed/index.ts`): una `service_role key` es un JWT sin `sub`, así que `auth.uid()` saldría
-- NULL y el filtro de bloqueos no filtraría nada -- SIN dar ningún error (punto 11 de
-- `edge-functions`). Por eso aquí NO se concede `execute` a `service_role`, a diferencia de las
-- siete funciones de escritura de arriba: si algún día alguien llama a este RPC con la clave de
-- servicio por error, falla cerrado con "permission denied for function" en vez de devolver un feed
-- sin filtrar en silencio.
--
-- `participants` viaja EMPAQUETADO dentro del propio RPC, no como una segunda consulta del cliente
-- contra `room_participants` filtrando `left_at is null` -- el grant de esa tabla a `authenticated`
-- (más arriba, § "Nace sin permisos") es `id, room_id, user_id, role, joined_at, hand_raised_at,
-- hand_raised_note`: **`left_at` no está**, a propósito, y PostgREST necesita privilegio de SELECT
-- sobre una columna para poder FILTRAR por ella, no solo para devolverla. Un `.is("left_at", null)`
-- desde `rooms-feed/index.ts` con el cliente del usuario da "permission denied for column left_at"
-- -- comprobado a mano reproduciendo esa consulta. Como esta función ya es `security definer`, es
-- el sitio correcto para resolverlo: agrega los participantes vivos de cada sala en un `jsonb` que
-- `_shared/rooms.ts#pickCardAvatars` puede consumir tal cual, sin pedir un grant nuevo.
create or replace function public.rooms_feed(p_category uuid default null)
returns table (
  id uuid, title text, category_id uuid, host_id uuid,
  host_name text, host_photo_path text,
  last_activity_at timestamptz, occupants int, participants jsonb
) language sql stable security definer set search_path = public as $$
  select r.id, r.title, r.category_id, r.host_id,
         pp.display_name as host_name, pp.photo_path as host_photo_path,
         r.last_activity_at,
         (select count(*)::int from room_participants p
           where p.room_id = r.id and p.left_at is null) as occupants,
         coalesce((
           select jsonb_agg(jsonb_build_object(
                    'userId', p.user_id, 'role', p.role, 'joinedAt', p.joined_at
                  ))
             from room_participants p
            where p.room_id = r.id and p.left_at is null
         ), '[]'::jsonb) as participants
    from rooms r
    left join public.public_profiles pp on pp.user_id = r.host_id
   where r.status = 'live'
     and (p_category is null or r.category_id = p_category)
     and not exists (
       select 1 from public.blocks b
        where (b.blocker_id = auth.uid() and b.blocked_id = r.host_id)
           or (b.blocker_id = r.host_id and b.blocked_id = auth.uid())
     )
   order by r.last_activity_at desc
   limit 100;
$$;

-- Por defecto `create function` concede EXECUTE a PUBLIC: se revoca y se concede a mano, solo a
-- `authenticated` (mismo patrón de los puntos 11-12 de `rls-security`, aplicado también a
-- `service_role` esta vez -- ver el porqué arriba).
revoke all on function public.rooms_feed(uuid) from public, anon, authenticated;
grant execute on function public.rooms_feed(uuid) to authenticated;

-- ROLLBACK:
-- revoke execute on function public.rooms_feed(uuid) from authenticated;
-- revoke all on function public.rooms_feed(uuid) from public, anon, authenticated;
-- drop function if exists public.rooms_feed(uuid);
-- revoke execute on function public.room_end(uuid, uuid)                from service_role;
-- revoke execute on function public.room_leave(uuid, uuid)               from service_role;
-- revoke execute on function public.room_revoke_speak(uuid, uuid, uuid)  from service_role;
-- revoke execute on function public.room_grant_speak(uuid, uuid, uuid)   from service_role;
-- revoke execute on function public.room_raise_hand(uuid, uuid, text)    from service_role;
-- revoke execute on function public.room_join(uuid, uuid)                from service_role;
-- revoke execute on function public.room_create(uuid, text, uuid)        from service_role;
-- revoke all on function public.room_end(uuid, uuid) from public, anon, authenticated;
-- revoke all on function public.room_leave(uuid, uuid) from public, anon, authenticated;
-- revoke all on function public.room_revoke_speak(uuid, uuid, uuid) from public, anon, authenticated;
-- revoke all on function public.room_grant_speak(uuid, uuid, uuid) from public, anon, authenticated;
-- revoke all on function public.room_raise_hand(uuid, uuid, text) from public, anon, authenticated;
-- revoke all on function public.room_join(uuid, uuid) from public, anon, authenticated;
-- revoke all on function public.room_create(uuid, text, uuid) from public, anon, authenticated;
-- drop function if exists public.room_end(uuid, uuid);
-- drop function if exists public.room_leave(uuid, uuid);
-- drop function if exists public.room_revoke_speak(uuid, uuid, uuid);
-- drop function if exists public.room_grant_speak(uuid, uuid, uuid);
-- drop function if exists public.room_raise_hand(uuid, uuid, text);
-- drop function if exists public.room_join(uuid, uuid);
-- drop function if exists public.room_create(uuid, text, uuid);
-- revoke execute on function public.room_max_speakers()  from service_role;
-- revoke execute on function public.room_max_occupants() from service_role;
-- revoke select, insert, update, delete on public.room_messages     from service_role;
-- revoke select, insert, update, delete on public.room_participants from service_role;
-- revoke select, insert, update, delete on public.rooms             from service_role;
-- drop index if exists public.room_participants_room_user_joined_idx;
-- drop function if exists public.room_max_speakers();
-- drop function if exists public.room_max_occupants();
-- drop table if exists public.room_messages;
-- drop table if exists public.room_participants;
-- drop table if exists public.rooms;
