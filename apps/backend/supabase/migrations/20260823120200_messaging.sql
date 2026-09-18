-- =================================================================================================
-- Fase 4 · Tarea 3 — `conversations`, `conversation_states` y `direct_messages`.
--
-- Plan: docs/superpowers/plans/2026-08-23-contactos-y-mensajeria.md (Tarea 3)
-- Spec: docs/spec-contactos-mensajes-conectar.md (§2.1, §2.2, §4.2, §4.6, §9.4)
-- ADR:  docs/decisions/0021-mensajeria-sin-confirmacion-de-lectura.md
--
-- Es la migración más delicada del plan: aquí RN-06, RN-23 y RN-31 se cumplen o se pierden, y las
-- tres se cumplen POR LA FORMA DE LAS TABLAS, no por disciplina del que escriba el endpoint.
--
--   RN-06 — al emisor nunca se le enseña que su conversación quedó en `ignored`. La garantía es que
--           `conversations` NO TIENE NI UN GRANT para `authenticated`: no hay consulta de cliente
--           que pueda devolver `status` ni `initiator_id`. Toda lectura pasa por Edge Function que
--           proyecta por espectador (Tarea 11).
--   RN-31 — no hay confirmación de lectura ni la habrá. `read_at` NO EXISTE (ADR 0021). Lo no leído
--           vive en `conversation_states.unread_count`, UNA FILA POR USUARIO con RLS
--           `auth.uid() = user_id`: no hay consulta que le devuelva al emisor el contador del otro.
--   RN-23 — ninguna respuesta revela un bloqueo. Por eso `conversations` NO tiene estado `blocked`:
--           el bloqueo vive en `blocks` (Tarea 6). Un estado que el bloqueado no debe poder deducir
--           no puede compartir fila con datos que algún día se le concedan.
-- =================================================================================================

-- =================================================================================================
-- 1) `conversations`
-- =================================================================================================

-- El par es ORDENADO (`user_a_id < user_b_id`) y único. Eso es lo que hace IMPOSIBLE el hilo
-- duplicado de RN-08 aunque dos peticiones crucen en el tiempo: sin el orden, (A,B) y (B,A) serían
-- dos filas distintas y el índice único no las vería como la misma conversación.
create table if not exists public.conversations (
  id           uuid primary key default gen_random_uuid(),
  user_a_id    uuid not null references public.profiles(user_id) on delete cascade,
  user_b_id    uuid not null references public.profiles(user_id) on delete cascade,
  -- 'ignored' es TERMINAL (RN-07) y NUNCA se le enseña al emisor (RN-06): en su lado la
  -- conversación se pinta igual que 'pending', para siempre. Por eso esta tabla no tiene
  -- ningún grant para `authenticated` — ver el bloque de grants.
  status       text not null default 'pending'
               check (status in ('pending', 'accepted', 'ignored')),
  initiator_id uuid not null references public.profiles(user_id) on delete cascade,
  -- Se lee: ventana móvil de 24 h del tope de primeros mensajes (RN-19).
  created_at      timestamptz not null default now(),
  -- Se lee: orden de la lista de Contactos (RN-29).
  last_message_at timestamptz not null default now(),
  constraint conversations_ordered_pair check (user_a_id < user_b_id)
);

create unique index if not exists conversations_pair_key
  on public.conversations (user_a_id, user_b_id);

-- `user_a_id` ya lo cubre el índice del par (es su primera columna); `user_b_id` no, y hace falta
-- para la mitad derecha de `where user_a_id = $1 or user_b_id = $1` —la lista de conversaciones de
-- un usuario— y para que el `on delete cascade` del borrado de cuenta no haga un seq scan.
create index if not exists conversations_user_b_id_idx
  on public.conversations (user_b_id);

-- `initiator_id` NO lleva índice a propósito: siempre es igual a `user_a_id` o a `user_b_id`, así
-- que ninguna consulta filtra por él sin filtrar antes por uno de los dos, y en el borrado de
-- cuenta la fila ya muere por la cascada de esos. Un índice más es coste en CADA escritura.

comment on table public.conversations is
  'Hilo 1:1 entre dos personas. NO tiene ningún grant para `authenticated`, y es deliberado: es lo '
  'que hace estructural —no confiada al cuidado de quien escriba el endpoint— la invisibilidad de '
  '`status = ''ignored''` (RN-06) y de `initiator_id`. Toda lectura pasa por Edge Function que '
  'proyecta por espectador (Tarea 11). NO hay estado ''blocked'': el bloqueo vive en `blocks` '
  '(Tarea 6), porque un estado que el bloqueado no debe poder deducir (RN-23) no puede compartir '
  'fila con datos que algún día se le concedan.';

-- =================================================================================================
-- 2) `conversation_states` — el estado POR USUARIO
-- =================================================================================================

create table if not exists public.conversation_states (
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  user_id         uuid not null references public.profiles(user_id) on delete cascade,
  -- RN-22: bloquear ARCHIVA la conversación en el lado del bloqueador, y solo en el suyo.
  hidden          boolean not null default false,
  notifications_enabled boolean not null default true,
  -- RN-31: lo no leído vive aquí, no en `direct_messages`. El `check` impide que un decremento mal
  -- hecho deje el contador en negativo, que en la UI se vería como una insignia absurda.
  unread_count    int not null default 0 check (unread_count >= 0),
  -- RN-27: "borrar historial" no borra los mensajes del otro. Marca desde cuándo ve ESTE usuario.
  cleared_at      timestamptz,
  primary key (conversation_id, user_id)
);

-- La PK empieza por `conversation_id`, así que "mis conversaciones" —la bandeja, que es la consulta
-- más frecuente de toda la mensajería— no la usa. De ahí este índice.
create index if not exists conversation_states_user_id_idx
  on public.conversation_states (user_id);

comment on table public.conversation_states is
  'Estado de una conversación PARA UN USUARIO: una fila por participante. RN-31 se cumple por la '
  'FORMA de esta tabla, no por disciplina: con RLS `auth.uid() = user_id`, no existe consulta que '
  'le devuelva al emisor el `unread_count` del receptor, así que no hay confirmación de lectura que '
  'filtrar (ADR 0021). Es también donde RN-22 archiva la conversación del bloqueador (`hidden`), y '
  'donde RN-27 recuerda desde cuándo ve cada uno (`cleared_at`).';

-- =================================================================================================
-- 3) `direct_messages`
-- =================================================================================================

-- SIN `read_at` y SIN `deleted_at` (ADR 0021). `read_at` está PROHIBIDA por RN-31 «ahora ni nunca»,
-- y estuvo dentro del ejemplo de la skill `db-schema` hasta el 2026-08-23: un bloque de ejemplo se
-- copia literalmente, así que valía tanto como una regla. `deleted_at` tampoco es el modelo de
-- borrado real — RN-28 pide dos modos, y son las dos columnas de abajo.
create table if not exists public.direct_messages (
  id              uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  sender_id       uuid not null references public.profiles(user_id) on delete cascade,
  content         text,
  -- RN-28: borrado lógico por usuario. Un mensaje con el id de X dentro no se le muestra a X.
  deleted_for     uuid[] not null default '{}',
  -- RN-28: borrado para todos. La fila sobrevive como lápida y `content` se pone a NULL: si el
  -- texto siguiera ahí, cualquier cliente que ignorase la bandera lo pintaría igual.
  deleted_for_all_at timestamptz,
  -- RN-28: tag "editado", visible para los dos.
  edited_at       timestamptz,
  reply_to_id     uuid references public.direct_messages(id) on delete set null,
  -- Idempotencia obligatoria de messaging-send (CLAUDE.md). Índice único parcial más abajo.
  idempotency_key uuid,
  created_at      timestamptz not null default now(),
  constraint direct_messages_content_or_tombstone check (
    (deleted_for_all_at is null
      and content is not null
      and char_length(btrim(content)) between 1 and 1000)
    or (deleted_for_all_at is not null and content is null)
  )
);

-- NOTA, y no es un olvido: aquí NO hay `kind`. El mensaje directo de Grasp es de TEXTO y solo de
-- texto, así que no hay un segundo tipo que distinguir — `docs/decisions/0006-la-mensajeria-es-solo-texto.md`.
-- Una columna de tipo con un único valor posible es una invitación a añadir el segundo sin pensarlo.
-- Consecuencia para el `check` de arriba: `content not null` fuera de la lápida es la regla completa,
-- no una versión provisional a la espera de relajarse.

-- Pagina la conversación (`order by created_at desc limit N`) Y acota la búsqueda del §9.4 a los
-- últimos 1000 mensajes. Un solo índice para las dos cosas.
create index if not exists direct_messages_conversation_created_idx
  on public.direct_messages (conversation_id, created_at desc);

-- Idempotencia de `messaging-send` (Tarea 10): un reintento con la misma clave devuelve el MISMO
-- mensaje. Parcial porque la inmensa mayoría de filas históricas no la necesitan, y porque en un
-- índice único normal todos los NULL serían distintos y el índice crecería sin aportar nada.
create unique index if not exists direct_messages_sender_idempotency_key
  on public.direct_messages (sender_id, idempotency_key)
  where idempotency_key is not null;

comment on column public.direct_messages.deleted_for is
  'RN-28, borrado "para mí": lista de usuarios que ya no deben ver este mensaje. La policy de '
  'lectura lo aplica con `not (auth.uid() = any(deleted_for))`, así que no depende de que el '
  'cliente filtre.';

-- =================================================================================================
-- 4) RLS
-- =================================================================================================

-- --- `conversations`: RLS activo y CERO POLICIES. Deny by default para todo el mundo salvo
--     `service_role`, que tiene BYPASSRLS. Es la mitad estructural de RN-06.
alter table public.conversations enable row level security;

-- --- `conversation_states`: cada uno ve y toca SOLO su fila. Es la mitad estructural de RN-31.
alter table public.conversation_states enable row level security;

drop policy if exists "conversation_states_read_own" on public.conversation_states;
create policy "conversation_states_read_own" on public.conversation_states
  for select
  to authenticated
  using (auth.uid() = user_id);

drop policy if exists "conversation_states_update_own" on public.conversation_states;
create policy "conversation_states_update_own" on public.conversation_states
  for update
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- Sin policy de INSERT ni de DELETE: las filas las crea `messaging-send` (Tarea 10) para los dos
-- participantes a la vez, y desaparecen por cascada. Si el cliente pudiera insertarlas, podría
-- fabricarse una fila en una conversación ajena y usarla para leer sus mensajes (ver la policy de
-- `direct_messages`, que deriva la participación de esta tabla).

-- --- `direct_messages`: lectura directa para que Supabase Realtime pueda entregar los mensajes
--     nuevos filtrando por RLS. Sin insert/update/delete: los escriben `messaging-send` y
--     `messaging-message-actions` con `service_role`.
alter table public.direct_messages enable row level security;

-- LA PARTICIPACIÓN SE DERIVA DE `conversation_states`, NO DE `conversations`, y es obligatorio que
-- sea así: la expresión de una policy se evalúa CON LOS PRIVILEGIOS DE QUIEN CONSULTA, y
-- `conversations` no tiene ni un grant para `authenticated`. Comprobado, no deducido: una policy que
-- consulta una tabla sin `SELECT` no devuelve cero filas, sino que aborta la consulta entera con
-- `ERROR: permission denied for table conversations`. Es decir, la versión "natural" de esta policy
-- —un `exists` contra `conversations`— rompería TODA la lectura de mensajes, y solo en ejecución.
--
-- Derivarla de `conversation_states` sale mejor por otra razón: `cleared_at` ya vive ahí, así que
-- RN-27 (tras borrar el historial solo se ve lo posterior) se aplica en la misma condición en vez
-- de en una segunda consulta que alguien podría olvidar.
drop policy if exists "direct_messages_read_participant" on public.direct_messages;
create policy "direct_messages_read_participant" on public.direct_messages
  for select
  to authenticated
  using (
    -- RN-28, borrado "para mí".
    not (auth.uid() = any(deleted_for))
    and exists (
      select 1
        from public.conversation_states cs
       where cs.conversation_id = direct_messages.conversation_id
         and cs.user_id = auth.uid()
         -- RN-27: nada anterior a mi propio borrado de historial.
         and (cs.cleared_at is null or direct_messages.created_at > cs.cleared_at)
    )
  );

-- =================================================================================================
-- 5) GRANTS — LOS TRES ROLES, EXPLÍCITOS (puntos 11 y 12 de rls-security)
--    Las tres tablas son NUEVAS: nacen sin ningún privilegio para ningún rol (punto 6b de
--    db-schema), así que no hace falta ningún `revoke` previo — solo conceder lo justo.
-- =================================================================================================

-- --- anon: NADA en las tres. No hay mensajería anónima.

-- --- authenticated:
--     `conversations` NO RECIBE NADA. Ni `select`. Es el invariante de esta migración: sin grant no
--     hay consulta de cliente que pueda leer `status` ni `initiator_id` (RN-06), y por tanto no hay
--     forma de que un descuido en un endpoint filtre que la conversación quedó en `ignored`.
grant select on public.direct_messages to authenticated;
grant select on public.conversation_states to authenticated;

--     Escritura de COLUMNA, nunca de tabla, sobre el estado propio. `unread_count` para poder marcar
--     como leído; `notifications_enabled` para el interruptor del menú de 3 puntos. `hidden` y
--     `cleared_at` NO se conceden: archivar es efecto de bloquear (RN-22) y vaciar el historial
--     (RN-27) son acciones con consecuencias, y las ejecuta `messaging-actions` con service_role.
grant update (unread_count, notifications_enabled) on public.conversation_states to authenticated;

-- --- service_role: BYPASSRLS, NO BYPASSGRANT (punto 12 de rls-security). Sin estos grants, TODAS
--     las Edge Functions de mensajería responden 500 "permission denied for table X" en cualquier
--     entorno creado desde cero — rama de preview, restore o `supabase start` limpio.
grant select, insert, update, delete on public.conversations       to service_role;
grant select, insert, update, delete on public.conversation_states to service_role;
grant select, insert, update, delete on public.direct_messages     to service_role;

-- =================================================================================================
-- 6) REALTIME — sin esto no hay entrega en tiempo real y EL FALLO ES MUDO
--    (la app simplemente no recibe nada, sin ningún error que lo delate).
-- =================================================================================================

-- Idempotente: `alter publication ... add table` es un error si la tabla ya está, y esta migración
-- tiene que poder reaplicarse en un `db reset`.
do $$
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    raise warning 'La publicacion supabase_realtime no existe: no hay entrega en tiempo real.';
  elsif not exists (
    select 1 from pg_publication_tables
     where pubname = 'supabase_realtime'
       and schemaname = 'public'
       and tablename = 'direct_messages'
  ) then
    alter publication supabase_realtime add table public.direct_messages;
  end if;
end $$;

-- Sobre `replica identity`: se deja la de por defecto (la PK) A PROPÓSITO. Realtime evalúa la RLS
-- del suscriptor contra el registro NUEVO, que en un UPDATE viaja completo, así que editar un
-- mensaje (RN-28) o añadir a alguien a `deleted_for` se entrega y se filtra bien. `replica identity
-- full` solo haría falta para eventos de DELETE, y aquí NO SE BORRAN FILAS: el borrado para todos
-- es una lápida (un UPDATE), justo para que la fila sobreviva. Si algún día se añade un DELETE real
-- sobre esta tabla, habrá que revisar esta decisión, porque duplica el WAL de cada escritura.

-- =================================================================================================
-- VERIFICACIÓN POSTERIOR (a mano tras aplicar; la migración no la hace)
-- =================================================================================================
--   select table_name, grantee, string_agg(distinct privilege_type, ',') as privs
--     from information_schema.table_privileges
--    where table_schema = 'public'
--      and table_name in ('conversations', 'conversation_states', 'direct_messages')
--      and grantee in ('anon', 'authenticated', 'service_role')
--    group by table_name, grantee order by table_name, grantee;
--   -- conversations       -> NI UNA FILA para anon ni para authenticated. Es el invariante.
--   -- conversation_states | authenticated | SELECT,UPDATE
--   -- direct_messages     | authenticated | SELECT
--
--   select tablename from pg_publication_tables where pubname = 'supabase_realtime';
--   -- direct_messages

-- =================================================================================================
-- ROLLBACK:
-- =================================================================================================
-- alter publication supabase_realtime drop table public.direct_messages;
-- revoke select, insert, update, delete on public.direct_messages     from service_role;
-- revoke select, insert, update, delete on public.conversation_states from service_role;
-- revoke select, insert, update, delete on public.conversations       from service_role;
-- revoke update (unread_count, notifications_enabled) on public.conversation_states from authenticated;
-- revoke select on public.conversation_states from authenticated;
-- revoke select on public.direct_messages from authenticated;
-- drop policy if exists "direct_messages_read_participant" on public.direct_messages;
-- drop policy if exists "conversation_states_update_own" on public.conversation_states;
-- drop policy if exists "conversation_states_read_own" on public.conversation_states;
-- drop table if exists public.direct_messages;
-- drop table if exists public.conversation_states;
-- drop table if exists public.conversations;
