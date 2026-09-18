-- =================================================================================================
-- Fase 4 · Tarea 6 — `blocks` y `reports`.
--
-- Plan: docs/superpowers/plans/2026-08-23-contactos-y-mensajeria.md (Tarea 6, decisión 6)
-- Spec: docs/spec-contactos-mensajes-conectar.md (§2.5, §2.6, §9.3, RN-22..RN-25, RN-07, RN-47)
--
-- ALCANCE DELIBERADO: lógica SENCILLA, no completa. Aquí solo viven las dos tablas y la lista de
-- cada usuario. La PROPAGACIÓN del bloqueo —archivar la conversación, excluir de Conectar en las dos
-- direcciones, impedir abrir hilo o solicitar seguimiento— es la Tarea 14 (`block-create` y
-- `report-create` con `service_role`).
--
-- Cuando se escribió esta migración, DESBLOQUEAR no entraba en la Fase 4 (línea en
-- `docs/pending-messaging.md`): no había camino de vuelta, el bloqueo era irreversible desde la app
-- y el modal de confirmación tenía que decirlo con esas palabras. Por eso `service_role` ya recibía
-- `delete` en `blocks`: la capacidad existía en la base para cuando hubiera pantalla.
--
-- Desde el 2026-08-30 esto ya no es cierto: `block-remove` deshace el bloqueo usando exactamente ese
-- `delete`. Ver docs/decisions/0027-el-bloqueo-deja-de-ser-irreversible.md.
--
-- RN-23 ES LA REGLA QUE MANDA EN ESTE FICHERO: ninguna respuesta puede revelar un bloqueo, ni por
-- texto ni por forma. Se cumple POR CONSTRUCCIÓN — el bloqueado no tiene fila que consultar — y no
-- por cuidado del que escriba el endpoint.
-- =================================================================================================

-- =================================================================================================
-- 1) LAS DOS TABLAS
-- =================================================================================================

create table if not exists public.blocks (
  blocker_id uuid not null references public.profiles(user_id) on delete cascade,
  blocked_id uuid not null references public.profiles(user_id) on delete cascade,
  -- Se lee: orden de la futura pantalla Configuración → Privacidad → Usuarios bloqueados.
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  constraint blocks_no_self check (blocker_id <> blocked_id)
);

create table if not exists public.reports (
  id              uuid primary key default gen_random_uuid(),
  reporter_id     uuid not null references public.profiles(user_id) on delete cascade,
  reported_id     uuid not null references public.profiles(user_id) on delete cascade,
  -- Desde dónde se reportó. Nullable: se podrá reportar desde un perfil, sin conversación.
  conversation_id uuid references public.conversations(id) on delete set null,
  created_at      timestamptz not null default now()
);

-- SIN `category` NI `reason`, y no es un olvido: esta fase no tiene formulario de justificación
-- (decisión 6 del plan), así que nadie las escribiría. Una columna que nadie escribe es una promesa
-- falsa en el esquema (punto 8 de db-schema): el siguiente que lea la tabla creerá que el motivo del
-- reporte está guardado en alguna parte. La Fase 10 las añade junto con su pantalla.

-- ESTAS NO SON TABLAS LÁPIDA (punto 4b de db-schema), y conviene tenerlo claro antes de "corregir"
-- el `on delete cascade` de las cuatro FK de usuario. La pregunta del punto 4b es si la fila hija
-- nace DURANTE el borrado del padre o tiene que sobrevivirle; aquí la respuesta es no a las dos:
-- un reporte sobre una cuenta ya borrada no tiene a quién moderar, y un bloqueo sobre alguien que ya
-- no existe no protege de nada. Por eso `cascade` es correcto aquí y sería un fallo en
-- `storage_gc_queue` o en `photo_audit_log`, que sí son lápidas.
comment on table public.blocks is
  'Lista de bloqueados de cada usuario (§2.5). RN-23 por construccion: solo la lee su `blocker_id`, '
  'asi que el BLOQUEADO NO TIENE FILA QUE CONSULTAR y ninguna consulta suya puede revelarle el '
  'bloqueo. `on delete cascade` es correcto y no es un descuido: no es una tabla lapida (punto 4b de '
  'db-schema), un bloqueo sobre una cuenta que ya no existe no protege de nada. DESBLOQUEAR no '
  'existe todavia en la app — ver docs/pending-messaging.md.';

comment on table public.reports is
  'Quien reporta a quien y desde que conversacion (§2.6). Nada mas: sin motivo, sin categorias y sin '
  'adjuntos, porque esta fase no tiene formulario (decision 6 del plan). La FASE 10 revisara la '
  'RETENCION de esta tabla junto con la cola de moderacion: es entonces cuando un reporte pasa a ser '
  'evidencia y no solo una preferencia del usuario, y `on delete cascade` puede dejar de valer.';

-- =================================================================================================
-- 2) ÍNDICE
-- =================================================================================================

-- La PK empieza por `blocker_id`, así que sirve para "¿a quién he bloqueado yo?". Pero RN-24 y
-- RN-47(2) exigen mirar el bloqueo EN CUALQUIER DIRECCIÓN, y esa mitad consulta por el bloqueado:
-- "¿me ha bloqueado alguien de esta lista?". Sin este índice, cada envío de mensaje y cada carga del
-- feed harían un seq scan.
create index if not exists blocks_blocked_id_idx on public.blocks (blocked_id);

-- `reports` no lleva índices todavía: hoy NADIE la consulta —no hay cola de moderación ni pantalla—
-- y un índice sobre una tabla que solo recibe inserciones es coste en cada escritura a cambio de
-- nada. La Fase 10 los añadirá con las consultas que los justifiquen.

-- =================================================================================================
-- 3) RLS
-- =================================================================================================

alter table public.blocks  enable row level security;
alter table public.reports enable row level security;

-- ESTA POLICY ES RN-23. Que sea `blocker_id` y no `blocker_id or blocked_id` es todo el diseño:
-- si el bloqueado pudiera leer la fila, sabría que le han bloqueado, que es exactamente lo que la
-- regla prohíbe. Con esto no hay consulta —ni por PostgREST, ni por Realtime, ni por un endpoint
-- descuidado que use el JWT del usuario— que se la pueda devolver.
drop policy if exists "blocks_read_own" on public.blocks;
create policy "blocks_read_own" on public.blocks
  for select
  to authenticated
  using (auth.uid() = blocker_id);

drop policy if exists "reports_read_own" on public.reports;
create policy "reports_read_own" on public.reports
  for select
  to authenticated
  using (auth.uid() = reporter_id);

-- Ninguna policy de escritura en las dos: las escriben `block-create` y `report-create` (Tarea 14)
-- con `service_role`, porque bloquear NO es insertar una fila — tiene efectos en otras tablas
-- (archivar la conversación del bloqueador, RN-22) que tienen que ocurrir en la misma transacción.
-- Si el cliente pudiera insertar directamente, existiría un bloqueo a medias: la fila puesta y la
-- propagación sin hacer.

-- =================================================================================================
-- 4) GRANTS — LOS TRES ROLES (puntos 11 y 12 de rls-security)
-- =================================================================================================

-- --- anon: nada en las dos.

-- --- authenticated: `select`. Es la "lista de bloqueados y reportados de cada usuario" de la
--     decisión 6, que EXISTE en la base aunque todavía no la pinte ninguna pantalla (la de
--     Configuración → Privacidad → Usuarios bloqueados es deuda declarada, no un olvido). El grant
--     no filtra nada de más: la policy de arriba ya acota a la fila propia.
grant select on public.blocks  to authenticated;
grant select on public.reports to authenticated;

-- --- service_role: `select, insert, delete`. SIN `update` a propósito: un bloqueo o un reporte se
--     crean o se retiran, nunca se modifican — no hay ninguna columna que tenga sentido cambiar
--     despues. `delete` está para el desbloqueo futuro y para la limpieza de la Fase 10.
--     El `set null` de `reports.conversation_id` cuando se borra una conversación NO necesita
--     `update`: los triggers de integridad referencial corren con los privilegios del dueño de la
--     tabla, no con los de quien lanza el borrado (punto 14 de rls-security).
grant select, insert, delete on public.blocks  to service_role;
grant select, insert, delete on public.reports to service_role;

-- =================================================================================================
-- VERIFICACIÓN POSTERIOR (a mano tras aplicar; la migración no la hace)
-- =================================================================================================
--   select table_name, grantee, string_agg(distinct privilege_type, ',') as privs
--     from information_schema.table_privileges
--    where table_schema = 'public' and table_name in ('blocks', 'reports')
--      and grantee in ('anon', 'authenticated', 'service_role')
--    group by table_name, grantee order by table_name, grantee;
--   -- blocks/reports | authenticated | SELECT
--   -- blocks/reports | service_role  | DELETE,INSERT,SELECT   <- sin UPDATE
--   -- anon           -> sin filas
--
--   -- Y la que de verdad importa, porque leer la policy NO basta: dos usuarios, y B no ve la fila
--   -- en la que A le bloqueó. apps/backend/supabase/tests/moderation-rls.sql

-- =================================================================================================
-- ROLLBACK:
-- =================================================================================================
-- revoke select, insert, delete on public.reports from service_role;
-- revoke select, insert, delete on public.blocks  from service_role;
-- revoke select on public.reports from authenticated;
-- revoke select on public.blocks  from authenticated;
-- drop policy if exists "reports_read_own" on public.reports;
-- drop policy if exists "blocks_read_own"  on public.blocks;
-- drop index if exists public.blocks_blocked_id_idx;
-- drop table if exists public.reports;
-- drop table if exists public.blocks;
