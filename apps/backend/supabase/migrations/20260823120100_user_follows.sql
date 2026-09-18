-- =================================================================================================
-- Fase 4 · Tarea 2 — `user_follows`: solicitudes y relaciones de seguimiento.
--
-- Plan: docs/superpowers/plans/2026-08-23-contactos-y-mensajeria.md (Tarea 2)
-- Spec: docs/spec-contactos-mensajes-conectar.md (§4.3 Follows: RN-11 a RN-17; §4.4 límites:
--       RN-18 a RN-21; §4.7 listas: RN-51)
--
-- Dos cosas que esta migración deja establecidas y que NO son detalles de implementación:
--
--   1) Las FK van contra `public.profiles(user_id)`, NO contra `auth.users`. Es lo que permite a
--      PostgREST incrustar el perfil directamente en la respuesta
--      (`follower:profiles!follower_id(display_name, tag, photo_path, preset_avatar)`), así que
--      listar seguidores/seguidos/solicitudes NO necesita una Edge Function dedicada. La cascada
--      sigue siendo correcta: `profiles.user_id` ya cascadea desde `auth.users` (borrar la cuenta
--      borra el perfil, que borra sus follows).
--
--   2) La lectura de esta tabla NO es `using (true)`, aunque hoy digan «pública» tanto el
--      documento maestro (`docs/Grasp-ClaudeCode-Bootstrap.md`, §9 fila `user_follows` y §10
--      "lectura pública... ") como la tabla de referencia de la skill `rls-security` (Sección 10,
--      fila `user_follows: pública | solo el propio follower_id`). Una solicitud en estado
--      `pending` revela que A intentó seguir a B ANTES de que B haya decidido nada (RN-12: la
--      solicitud vive en Perfil → Seguidores → Solicitudes de seguimiento, con Aceptar/Rechazar)
--      — eso no es información pública, es justo la clase de dato que un tercero C no debería
--      poder leer nunca. La policy de este fichero es DELIBERADAMENTE más estricta que esas dos
--      fuentes.
--
--      NO "arregles" esto para volver a `using (true)` por hacerlo coincidir con el maestro o con
--      la skill, sin releer antes el precedente del punto 6 de `rls-security` (el del teléfono):
--      una frase escrita en un documento no es el estado del sistema. Aquí es al revés de aquel
--      precedente — el estado real (esta migración) es MÁS estricto que lo que las dos fuentes
--      prometen, no menos — pero el riesgo de que alguien "corrija" el código para que encaje con
--      el documento es el mismo. La corrección de esas dos fuentes queda fuera del alcance de la
--      Tarea 2 (ver `docs/superpowers/plans/2026-08-23-contactos-y-mensajeria.md`); esta migración
--      solo dejaba dicho que la divergencia es intencional, no un olvido.
-- =================================================================================================

-- =================================================================================================
-- 1) LA TABLA
-- =================================================================================================
create table if not exists public.user_follows (
  follower_id uuid not null references public.profiles(user_id) on delete cascade,
  followee_id uuid not null references public.profiles(user_id) on delete cascade,
  status      text not null default 'pending' check (status in ('pending', 'accepted')),
  -- Se lee: ordena la lista de seguidores y cuenta las solicitudes del día (RN-20).
  created_at  timestamptz not null default now(),
  primary key (follower_id, followee_id),
  constraint user_follows_no_self check (follower_id <> followee_id)
);

comment on column public.user_follows.status is
  'pending: A solicitó seguir a B y B no ha decidido. accepted: B aceptó (RN-13, unidireccional). '
  'NO hay estado "rejected": rechazar (RN-16) borra la fila entera, porque un follow rechazado '
  'puede volver a solicitarse sin dejar rastro — a diferencia de una solicitud de mensaje.';

comment on column public.user_follows.created_at is
  'Orden de la lista de seguidores/seguidos y base del tope diario de solicitudes (RN-20, índice '
  'parcial user_follows_follower_pending_created_at_idx).';

-- =================================================================================================
-- 2) ÍNDICES
--    Las dos columnas de la FK ya quedan cubiertas: follower_id por ser la primera de la PK,
--    followee_id por el índice de abajo. Ninguno de los dos duplica al índice de la PK (que es
--    sobre TODOS los status, no solo 'pending', y empieza por follower_id, no por followee_id).
-- =================================================================================================

-- Lista de seguidores de un perfil (status = 'accepted') y contador de solicitudes recibidas
-- pendientes (status = 'pending') de RN-51 — las dos consultas filtran por followee_id primero.
create index if not exists user_follows_followee_status_idx
  on public.user_follows (followee_id, status);

-- Tope diario de 20 solicitudes ENVIADAS (RN-20): cuenta filas de un follower_id concreto con
-- created_at dentro de las últimas 24h. Parcial sobre 'pending' a propósito — es el único status
-- que cuenta para el tope, y así el índice no arrastra las filas 'accepted', que son la mayoría a
-- medida que la cuenta envejece.
create index if not exists user_follows_follower_pending_created_at_idx
  on public.user_follows (follower_id, created_at)
  where status = 'pending';

-- =================================================================================================
-- 3) RLS — deny by default, una sola policy de LECTURA. Sin policy de escritura para NADIE:
--
--    - Los contadores de `profiles` (followers_count/following_count) los mueve `follow-toggle`
--      (Tarea 8) con service_role, en la misma transacción que el insert/update/delete de esta
--      tabla — si `authenticated` pudiera escribir directo, los contadores y las filas podrían
--      desincronizarse con un PATCH suelto por PostgREST.
--    - RN-24 ("un bloqueado no puede solicitar seguimiento") no es expresable en un `with check`
--      de esta tabla sola: hace falta consultar `blocks` (Tarea 6, todavía no existe en este
--      punto del plan) Y decidir en qué dirección se aplica. Es lógica de negocio, no una
--      invariante de fila — vive en la Edge Function.
-- =================================================================================================
alter table public.user_follows enable row level security;

drop policy if exists "user_follows_read_own_or_accepted" on public.user_follows;
create policy "user_follows_read_own_or_accepted" on public.user_follows
  for select
  to authenticated
  using (status = 'accepted' or auth.uid() in (follower_id, followee_id));

-- =================================================================================================
-- 4) GRANTS — LOS TRES ROLES, EXPLÍCITOS (puntos 11 y 12 de rls-security)
--    `user_follows` es tabla NUEVA: nace sin ningún privilegio para ningún rol (punto 6b de
--    db-schema — los default privileges de `public` no conceden nada a anon/authenticated desde
--    `20260809142046`, ni a service_role desde `20260810160000`). No hace falta ningún `revoke`
--    aquí, solo conceder lo que cada rol necesita. Verificación real al final del fichero.
-- =================================================================================================

-- --- anon: nada. No hay caso de uso anónimo para follows — a diferencia de `categories` o
--     `badges`, esta tabla puede revelar una solicitud pendiente (ver bloque de arriba), así que
--     ni siquiera se plantea un `select` público.

-- --- authenticated: solo lectura, y de TABLA (no de columna). Ninguna de las cuatro columnas es
--     dato del Art. 9 RGPD — a diferencia de `profiles`/`profiles_private`, aquí no hay frontera
--     que trazar dentro de la fila. La policy de arriba ya decide QUÉ FILAS; este grant decide que
--     puede leer las que la policy le deje ver. Sin insert/update/delete: esos verbos los mueve
--     `follow-toggle` con service_role (ver punto 3).
grant select on public.user_follows to authenticated;

-- --- service_role: BYPASSRLS, no BYPASSGRANT (punto 12 de rls-security) — sin esto,
--     `follow-toggle` respondería 500 "permission denied for table user_follows" en cualquier
--     entorno creado desde cero. Los cuatro verbos: SELECT para comprobar estado antes de decidir
--     aceptar/rechazar y para el tope de RN-20, INSERT para la solicitud, UPDATE para aceptar
--     (pending -> accepted) y DELETE para rechazar / dejar de seguir / quitar seguidor.
grant select, insert, update, delete on public.user_follows to service_role;

-- =================================================================================================
-- VERIFICACIÓN POSTERIOR (a mano tras aplicar; la migración no la hace)
-- =================================================================================================
--   select grantee, string_agg(distinct privilege_type, ',' order by privilege_type) as privs
--     from information_schema.table_privileges
--    where table_schema = 'public' and table_name = 'user_follows'
--      and grantee in ('anon', 'authenticated', 'service_role')
--    group by grantee order by grantee;
--   -- authenticated | SELECT
--   -- service_role  | DELETE,INSERT,SELECT,UPDATE
--   -- anon          -> sin filas
--
--   select polname, permissive, roles, cmd, qual
--     from pg_policies where schemaname = 'public' and tablename = 'user_follows';
--   -- user_follows_read_own_or_accepted | PERMISSIVE | {authenticated} | SELECT |
--   --   (status = 'accepted'::text) OR (auth.uid() = ANY (ARRAY[follower_id, followee_id]))

-- =================================================================================================
-- ROLLBACK:
-- =================================================================================================
-- revoke select, insert, update, delete on public.user_follows from service_role;
-- revoke select on public.user_follows from authenticated;
-- drop policy if exists "user_follows_read_own_or_accepted" on public.user_follows;
-- drop index if exists public.user_follows_follower_pending_created_at_idx;
-- drop index if exists public.user_follows_followee_status_idx;
-- drop table if exists public.user_follows;
