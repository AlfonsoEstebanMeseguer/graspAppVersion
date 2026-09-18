-- Baseline consolidado: sustituye a las 15 migraciones de esquema/RLS/grants del historial
-- 20260808..20260816 (excluye las 4 de crons y la de seed, que viven en los otros dos
-- ficheros del baseline). Decisión y prueba de equivalencia: docs/decisions/0017-consolidar-las-migraciones-en-tres.md.
-- Tabla de correspondencia completa (migración vieja → qué hacía → dónde vive ahora):
-- apps/backend/supabase/migrations/README.md.
--
-- Este fichero es IDEMPOTENTE a propósito (`create table if not exists`, `drop policy if
-- exists` + `create policy`, `create or replace function`, revoke+grant): puede aplicarse
-- tanto sobre una base vacía como sobre un entorno que ya tenga este esquema, para poder
-- reconciliar producción sin `db reset`. Ver el procedimiento de producción en el ADR 0017.
--
-- Lo que sigue NO es un resumen mudo de "qué tablas hay": cada bloque no obvio conserva el
-- porqué que motivó su forma actual, porque las 19 migraciones originales eran el mejor
-- activo documental del backend (auditoría del 2026-08-15) y un squash que lo perdiera
-- destruiría más de lo que ahorra. Para el detalle completo de cada incidente, la migración
-- original citada en cada comentario sigue en el historial de git.

-- =====================================================================================
-- 1) CATEGORIES — catálogo de temas de apoyo
-- =====================================================================================
create table if not exists public.categories (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  slug text not null unique,
  -- cascade por decisión de PRODUCTO, no recomendación técnica: se propuso `restrict`
  -- (borrar una categoría padre arrastra toda su descendencia en cadena, sin aviso) y se
  -- descartó a propósito. Mitigación pendiente: ver "Desacuerdo registrado" en
  -- .claude/agent-memory/db-agent/MEMORY.md. Origen: 20260808000000.
  parent_id uuid references public.categories(id) on delete cascade
);

create index if not exists categories_parent_id_idx on public.categories (parent_id);

alter table public.categories enable row level security;

drop policy if exists "categories_read_public" on public.categories;
create policy "categories_read_public" on public.categories
  for select
  using (true);
-- Sin policy de escritura: el catálogo lo mantiene service_role (deny by default).
-- Sin `to authenticated`: la policy aplica también a `anon`, deliberado desde el origen —
-- pero el GRANT de abajo no concede nada a `authenticated` ni a `anon` sobre esta tabla, así
-- que hoy solo la lee `service_role` desde `onboarding-catalogs`. La policy pública queda
-- lista para el día en que se sirva un catálogo de categorías sin sesión.

-- =====================================================================================
-- 2) PROFILES — cara PÚBLICA del perfil. RLS filtra FILAS, nunca columnas: todo lo que
--    esté aquí lo puede leer cualquier `authenticated`. Lo sensible va en profiles_private.
-- =====================================================================================
create table if not exists public.profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  -- Obligatorio desde el 2026-08-17 (ADR 0018). El `not null` aquí solo cubre las bases
  -- creadas desde cero; el `alter column ... set not null` de abajo cubre las que ya existían,
  -- porque `create table if not exists` no altera la definición de una tabla presente.
  display_name text not null,
  -- `photo_url` se conserva por compatibilidad de lectura del cliente; ya no es escribible
  -- (ver grants) ni es la fuente de verdad del avatar — lo es `photo_path`/`preset_avatar`.
  photo_url text,
  language text default 'es',
  -- level..following_count son territorio exclusivo de service_role (ver grants): son
  -- entitlements/contadores, y CLAUDE.md prohíbe que el cliente los escriba directamente.
  level int default 1,
  xp int default 0,
  reputation_score int default 100,
  time_helping_seconds int default 0,
  gifts_received_count int default 0,
  vip_status bool default false,
  streak_days int default 0,
  followers_count int default 0,
  following_count int default 0,
  -- Se lee: "miembro desde" en el perfil. Origen: 20260808000000.
  created_at timestamptz not null default now(),
  -- "Salas participadas", primer cuadro del boceto 08-profile.jpeg. La escribirá
  -- `room-actions` (Fase 5); el grant de abajo garantiza que el cliente no pueda tocarla.
  -- Origen: 20260809120000 (sustituyó a badges_count/experiences_count, retiradas por ser
  -- estado duplicado y falsificable una vez existieron user_badges/user_experiences reales).
  rooms_joined_count int not null default 0,
  -- Clave del objeto en R2 (`avatars/{user_id}/{uuid}.webp`), NUNCA la URL ni los bytes.
  -- La escribe solo `profile-avatar-set` con service_role. Origen: 20260809150000.
  photo_path text,
  -- Slug de uno de los 8 avatares predeterminados (assets locales de Flutter, no objetos de
  -- R2 — ver el `check` de abajo). Origen: 20260813090000.
  preset_avatar text
  -- NOTA: `phone_number` existió aquí desde el baseline y se BORRÓ en 20260816090000
  -- (H-S-01: era legible por cualquier `authenticated` vía `grant select` de tabla + policy
  -- `using (true)`, con un índice que hacía instantánea la búsqueda inversa — doxing en una
  -- app de salud mental). No reaparece: lo que no se almacena no se puede volver a filtrar.
);

alter table public.profiles enable row level security;

drop policy if exists "profiles_read_public" on public.profiles;
create policy "profiles_read_public" on public.profiles
  for select
  to authenticated
  using (true);

drop policy if exists "profiles_insert_own" on public.profiles;
create policy "profiles_insert_own" on public.profiles
  for insert
  to authenticated
  with check (auth.uid() = user_id);

drop policy if exists "profiles_update_own" on public.profiles;
create policy "profiles_update_own" on public.profiles
  for update
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- Dominio cerrado de los 8 avatares predeterminados. Es un CHECK, no una convención, porque
-- el riesgo real es que alguien "unifique" el predeterminado como una clave de R2: si
-- `photo_path` guardase una ruta compartida, el primer usuario que cambiase de avatar la
-- encolaría en storage_gc_queue y media-gc-cron la borraría, rompiendo la imagen de TODOS
-- los que la hubieran elegido. Esta columna no puede contener físicamente una clave de R2.
-- Lista duplicada A PROPÓSITO en _shared/avatar-set.ts (400 legible) y AvatarType (Flutter);
-- esta migración es la autoridad si divergen. Origen: 20260813090000.
alter table public.profiles drop constraint if exists profiles_preset_avatar_valid;
alter table public.profiles
  add constraint profiles_preset_avatar_valid
  check (
    preset_avatar is null
    or preset_avatar in (
      'gym', 'reader', 'music', 'coding', 'animal',
      'normal_1', 'normal_2', 'normal_3'
    )
  );

-- Un avatar por persona: privacidad, no solo coherencia. Guardar la foto de alguien que
-- eligió un dibujo para dejar de enseñar la cara es conservar un dato que creía haber
-- quitado. Origen: 20260813090000.
alter table public.profiles drop constraint if exists profiles_avatar_exclusive;
alter table public.profiles
  add constraint profiles_avatar_exclusive
  check (photo_path is null or preset_avatar is null);

-- El nombre es OBLIGATORIO, y hacen falta DOS constraints porque hacen trabajos distintos:
--   - la CHECK acota el CONTENIDO (ni en blanco, ni más de 60 caracteres);
--   - `not null` es lo único que prohíbe la AUSENCIA. Una CHECK de Postgres se satisface
--     cuando la expresión da TRUE **o NULL**, así que `char_length(btrim(null))` la pasaría.
-- `btrim` porque `char_length('   ')` es 3: sin él, tres espacios contaban como nombre.
--
-- Hasta el 2026-08-17 la constraint era `display_name is null or char_length(...) between 1
-- and 60` y además `not valid`: acotaba la longitud y NO la presencia, así que un perfil sin
-- nombre entraba por los tres caminos de escritura a la vez — el trigger de alta (que hacía
-- `nullif(...,'')`), un PATCH directo a PostgREST (el grant de columna incluye display_name) y
-- el propio formulario de registro, que validaba fecha y género pero no el nombre. H-SV-03
-- aplicado a medias: media regla aplicada parece la regla entera. Ver ADR 0018.
--
-- Sin `not valid`: eso solo se salta el escaneo único de las filas existentes al crear la
-- constraint (no reduce ninguna comprobación posterior), y sirve para tablas grandes y vivas.
-- `profiles` tiene 1 fila en producción, así que el escaneo es gratis y dejarla sin validar
-- solo haría que el esquema afirmara algo que nadie ha comprobado.

-- Sanea lo que incumpla ANTES del `not null`. En una base recién creada no toca nada; en una
-- que ya existía rellena con un marcador deliberadamente feo, para que si aparece en una
-- pantalla cante que es un dato roto en vez de pasar por un nombre real.
do $$
declare
  v_afectadas int;
begin
  update public.profiles
     set display_name = 'Usuario ' || left(user_id::text, 8)
   where display_name is null
      or btrim(display_name) = '';

  get diagnostics v_afectadas = row_count;

  if v_afectadas > 0 then
    raise notice 'display_name: % perfil(es) sin nombre rellenados con marcador.', v_afectadas;
  end if;
end $$;

alter table public.profiles drop constraint if exists profiles_display_name_length_chk;
alter table public.profiles
  add constraint profiles_display_name_length_chk
  check (char_length(btrim(display_name)) between 1 and 60);

-- Redundante en una base recién creada (la columna ya nace `not null` arriba); necesario en un
-- entorno que ya tuviera la tabla, donde el `create table if not exists` fue un no-op.
alter table public.profiles alter column display_name set not null;

-- =====================================================================================
-- 3) PROFILES_PRIVATE — datos sensibles: solo el propio usuario. La categoría de apoyo
--    revela situación de salud mental (Art. 9 RGPD): nunca puede ser legible por terceros.
--    El emparejamiento por categoría lo resuelve una Edge Function con service_role.
-- =====================================================================================
create table if not exists public.profiles_private (
  user_id uuid primary key references auth.users(id) on delete cascade,
  country text,
  -- Siempre NULL a propósito: `birth_date` es la única fuente de verdad y la edad se deriva
  -- al leerla. Materializarla crearía un dato que envejece mal (falso desde el siguiente
  -- cumpleaños, sin nada que lo actualice).
  age int,
  gender text,
  birth_date date,
  primary_category_id uuid references public.categories(id) on delete set null,
  secondary_categories uuid[]
);

create index if not exists profiles_private_primary_category_id_idx
  on public.profiles_private (primary_category_id);

alter table public.profiles_private enable row level security;

drop policy if exists "profiles_private_read_own" on public.profiles_private;
create policy "profiles_private_read_own" on public.profiles_private
  for select
  to authenticated
  using (auth.uid() = user_id);

drop policy if exists "profiles_private_insert_own" on public.profiles_private;
create policy "profiles_private_insert_own" on public.profiles_private
  for insert
  to authenticated
  with check (auth.uid() = user_id);

drop policy if exists "profiles_private_update_own" on public.profiles_private;
create policy "profiles_private_update_own" on public.profiles_private
  for update
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- `not valid` por el mismo motivo que display_name_length. H-SV-03, origen: 20260816090000.
alter table public.profiles_private drop constraint if exists profiles_private_gender_chk;
alter table public.profiles_private
  add constraint profiles_private_gender_chk
  check (gender is null or gender in ('hombre', 'mujer', 'otro'))
  not valid;

-- =====================================================================================
-- 4) ONBOARDING_RESPONSES — respuestas del cuestionario que alimenta match-feed.
--    Una fila por usuario: se sobrescribe (upsert), no se acumula historial.
-- =====================================================================================
create table if not exists public.onboarding_responses (
  user_id uuid primary key references auth.users(id) on delete cascade,
  responses jsonb not null default '{}'::jsonb,
  -- Se lee: saber si el onboarding está desactualizado respecto a un cuestionario más
  -- nuevo. Requiere el trigger de abajo (default now() solo corre en el INSERT).
  updated_at timestamptz not null default now()
);

alter table public.onboarding_responses enable row level security;

drop policy if exists "onboarding_responses_select_own" on public.onboarding_responses;
create policy "onboarding_responses_select_own" on public.onboarding_responses
  for select
  to authenticated
  using (auth.uid() = user_id);

drop policy if exists "onboarding_responses_insert_own" on public.onboarding_responses;
create policy "onboarding_responses_insert_own" on public.onboarding_responses
  for insert
  to authenticated
  with check (auth.uid() = user_id);

drop policy if exists "onboarding_responses_update_own" on public.onboarding_responses;
create policy "onboarding_responses_update_own" on public.onboarding_responses
  for update
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- =====================================================================================
-- 5) BADGES (catálogo) — escritura solo service_role
-- =====================================================================================
-- Se propuso apuntar `user_badges.badge_id` a `categories` "para prototipar". Descartado:
-- `categories` alimenta el algoritmo de afinidad, y meter insignias ahí las volvería
-- seleccionables como situación en el onboarding. Origen: 20260809120000.
create table if not exists public.badges (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  name text not null,
  description text,
  -- Nombre del icono de Material. Cuando existan SVG de marca en assets/icons/ pasa a
  -- guardar el nombre del asset.
  icon text,
  -- Orden estable en la parrilla de "Ver todas".
  sort_order int not null default 0
);

alter table public.badges enable row level security;

drop policy if exists "badges_read_public" on public.badges;
create policy "badges_read_public" on public.badges
  for select
  to authenticated
  using (true);

-- =====================================================================================
-- 6) USER_BADGES — quién ha ganado qué. PK compuesta: un usuario gana muchas insignias.
--    Lectura pública entre authenticated (no revela nada sensible); sin escritura: conceder
--    una insignia es decisión de backend. Origen: 20260809120000.
-- =====================================================================================
create table if not exists public.user_badges (
  user_id uuid not null references auth.users(id) on delete cascade,
  badge_id uuid not null references public.badges(id) on delete cascade,
  -- La UI ordena por más reciente y marca las recién ganadas.
  earned_at timestamptz not null default now(),
  primary key (user_id, badge_id)
);

alter table public.user_badges enable row level security;

drop policy if exists "user_badges_read_public" on public.user_badges;
create policy "user_badges_read_public" on public.user_badges
  for select
  to authenticated
  using (true);

-- =====================================================================================
-- 7) EXPERIENCE_CASES (catálogo de casos concretos, pregunta 2 del onboarding)
-- =====================================================================================
-- `category_id` es el puente hacia el tema de apoyo y vive en BD (no en Flutter) porque es
-- entrada del algoritmo de afinidad: si el mapeo viviera en el cliente, una app modificada
-- podría mentir sobre a qué categoría pertenece su respuesta. Origen: 20260809120000.
create table if not exists public.experience_cases (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  label text not null,
  category_id uuid references public.categories(id) on delete set null,
  icon text,
  sort_order int not null default 0
);

create index if not exists experience_cases_category_id_idx
  on public.experience_cases (category_id);

alter table public.experience_cases enable row level security;

drop policy if exists "experience_cases_read_public" on public.experience_cases;
create policy "experience_cases_read_public" on public.experience_cases
  for select
  to authenticated
  using (true);

-- =====================================================================================
-- 8) USER_EXPERIENCES — qué ha vivido cada usuario. LECTURA SOLO DEL DUEÑO.
-- =====================================================================================
-- "Hace poco rompí con mi pareja" o "tengo ansiedad por exámenes" es dato de salud y vida
-- privada (Art. 9 RGPD) — el mismo motivo por el que profiles_private existe. Si
-- primary_category_id no puede leerlo un tercero, el caso concreto, que revela más,
-- tampoco. El emparejamiento lo resuelve match-feed con service_role. Origen: 20260809120000.
create table if not exists public.user_experiences (
  user_id uuid not null references auth.users(id) on delete cascade,
  experience_case_id uuid not null references public.experience_cases(id) on delete cascade,
  recorded_at timestamptz not null default now(),
  primary key (user_id, experience_case_id)
);

alter table public.user_experiences enable row level security;

drop policy if exists "user_experiences_read_own" on public.user_experiences;
create policy "user_experiences_read_own" on public.user_experiences
  for select
  to authenticated
  using (auth.uid() = user_id);
-- Sin policy de escritura: las escribe `onboarding-complete` con service_role.

-- =====================================================================================
-- 9) STORAGE_GC_QUEUE — cola de recogida de basura en R2 para fotos de perfil.
-- =====================================================================================
-- TABLA LÁPIDA: existe para sobrevivir al usuario, así que NO lleva FK contra auth.users.
-- El trigger `profiles_on_delete_queue_photo` la rellena DURANTE la cascada de borrado,
-- cuando la fila de auth.users ya no existe: con FK, `delete from auth.users` fallaba con
-- 23503 (no se podía borrar la cuenta — Art. 17 RGPD incumplido). Corregido en 20260810140000
-- tras detectarse con el camino de borrado REAL (`delete from auth.users`, no `delete from
-- profiles`, que sí satisfacía la FK y ocultaba el fallo). Ver skill db-schema punto 4b/4c.
create table if not exists public.storage_gc_queue (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  photo_path text not null,
  created_at timestamptz not null default now(),
  status text not null default 'pending' check (status in ('pending', 'deleted', 'failed')),
  -- Intentos de borrado en R2 consumidos. Al llegar a 5, media-gc-cron pasa la fila a
  -- 'failed' (terminal) y deja de reintentarla — 'failed' NO es el destino de cualquier
  -- fallo, es un estado terminal que solo se alcanza agotando los reintentos (sin esto, un
  -- único timeout transitorio de R2 dejaba el objeto vivo para siempre, con la fila marcada
  -- como si el asunto estuviera cerrado). Origen: 20260810150000.
  attempts int not null default 0,
  -- Motivo del último fallo: sin esto, diagnosticar un fallo intermitente exige reproducirlo.
  last_error text,
  last_attempt_at timestamptz
);

comment on column public.storage_gc_queue.user_id is
  'Dueño de la foto encolada. Sin FK a auth.users a propósito: la fila se crea durante '
  'el borrado en cascada del usuario y tiene que sobrevivirle hasta que media-gc-cron '
  'borre el objeto de R2. Ver 20260810140000_fix_account_deletion_cascade.sql.';
comment on column public.storage_gc_queue.attempts is
  'Intentos de borrado en R2 consumidos. Al llegar a 5, media-gc-cron pasa la fila a '
  'status=''failed'' (terminal) y deja de reintentarla.';
comment on column public.storage_gc_queue.last_error is
  'Motivo del último fallo, para no tener que reproducir un error intermitente.';

-- Orden de drenado: las filas más antiguas —las que más llevan incumpliendo el borrado—
-- salen primero sin ordenar en memoria. Sustituye al índice original sobre `status` solo
-- (idx_storage_gc_queue_status), retirado en 20260810160000.
drop index if exists public.idx_storage_gc_queue_status;
create index if not exists idx_storage_gc_queue_pending
  on public.storage_gc_queue (created_at)
  where status = 'pending';

create index if not exists idx_storage_gc_queue_user on public.storage_gc_queue (user_id);

alter table public.storage_gc_queue enable row level security;

drop policy if exists "users_read_own_gc_queue" on public.storage_gc_queue;
create policy "users_read_own_gc_queue" on public.storage_gc_queue
  for select
  using (auth.uid() = user_id);

-- =====================================================================================
-- 10) PHOTO_AUDIT_LOG — evidencia de cumplimiento (Art. 6.1.c RGPD). Persiste tras el
--     borrado de cuenta; retención de 90 días la aplica el cron de baseline_crons.sql.
-- =====================================================================================
-- TABLA LÁPIDA por el mismo motivo que storage_gc_queue, y con el mismo precedente: la FK
-- original era `on delete restrict`, que hacía justo lo contrario de lo que pretendía —
-- en vez de "sobrevivir al borrado", IMPEDÍA el borrado. Corregido en 20260810140000.
create table if not exists public.photo_audit_log (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  photo_path text,
  action text not null,
  created_at timestamptz not null default now()
);

comment on column public.photo_audit_log.user_id is
  'Usuario que subió la foto. Sin FK a auth.users a propósito: el registro es evidencia '
  'de cumplimiento (Art. 6.1.c) y persiste tras el borrado de la cuenta. El '
  'on delete restrict anterior no conservaba nada: impedía borrar la cuenta.';

create index if not exists idx_photo_audit_log_user on public.photo_audit_log (user_id);
create index if not exists idx_photo_audit_log_created_at on public.photo_audit_log (created_at);

alter table public.photo_audit_log enable row level security;

drop policy if exists "only_own_user_sees_audit" on public.photo_audit_log;
create policy "only_own_user_sees_audit" on public.photo_audit_log
  for select
  using (auth.uid() = user_id);

-- =====================================================================================
-- 11) MEDIA_RECONCILE_RUNS — registro de ejecuciones del barrido de huérfanos de R2.
-- =====================================================================================
-- Sin esta tabla hay tres fallos sin ninguna señal: que el barrido dejó de correr (un cron
-- muerto no genera evento propio — precedente: pg_net es asíncrono y cron.job_run_details
-- decía 'succeeded' mientras la función devolvía 401), que el freno de emergencia saltó, o
-- que apareció un prefijo desconocido en el bucket. `ops-digest-cron` la lee para el email
-- diario. NO lleva user_id ni ninguna clave ajena: es una tabla de operación, no de usuario
-- — no hay a quién referenciar. Origen: 20260810180000.
create table if not exists public.media_reconcile_runs (
  id               uuid primary key default gen_random_uuid(),
  started_at       timestamptz not null default now(),
  -- null si la ejecución no llegó a terminar. El digest usa max(finished_at) para saber si
  -- el barrido sigue vivo.
  finished_at      timestamptz,
  objects_scanned  int         not null default 0,
  orphans_found    int         not null default 0,
  -- Siempre 0 cuando aborted_reason no es null: el freno se evalúa ANTES de encolar.
  orphans_enqueued int         not null default 0,
  -- null = ejecución sana. NO es un enum cerrado: no construir un consumidor por igualdad
  -- exacta. Frenos puros (evaluateBrake en _shared/reconcile.ts): referenced_set_truncated,
  -- referenced_set_empty, too_many_orphans, orphan_ratio_too_high. El handler añade además
  -- query_failed, enqueue_failed y el dinámico r2_list_failed: <motivo>.
  aborted_reason   text,
  unknown_prefixes text[]      not null default '{}'
);

comment on table public.media_reconcile_runs is
  'Una fila por ejecución de media-reconcile-cron. La lee ops-digest-cron para detectar que el barrido '
  'murió, que el freno saltó, o que hay prefijos sin cablear.';
comment on column public.media_reconcile_runs.finished_at is
  'null si la ejecución no llegó a terminar. El digest usa max(finished_at) para saber si el barrido vive.';
comment on column public.media_reconcile_runs.orphans_enqueued is
  'Siempre 0 cuando aborted_reason no es null: el freno se evalúa ANTES de encolar.';
comment on column public.media_reconcile_runs.aborted_reason is
  'null = ejecución sana. NO es un enum cerrado: no construir un consumidor por igualdad exacta. '
  'Frenos puros (evaluateBrake en _shared/reconcile.ts): referenced_set_truncated, '
  'referenced_set_empty, too_many_orphans, orphan_ratio_too_high. El handler añade además '
  'query_failed, enqueue_failed y el DINÁMICO r2_list_failed: <motivo> (mensaje de error de R2 '
  'truncado a 200 caracteres). Ver media-reconcile-cron/index.ts. '
  'referenced_set_truncated significa que una consulta del conjunto referenciado se leyó incompleta '
  '(PostgREST recorta en max_rows sin devolver error): las filas que faltan harían pasar por '
  'huérfanas a fotos vivas, así que no se encola nada. La respuesta HTTP dice en truncated_sources '
  'qué tabla descuadró.';

create index if not exists idx_media_reconcile_runs_last_ok
  on public.media_reconcile_runs (finished_at desc)
  where aborted_reason is null;

-- Deny by default, sin ninguna policy: ningún usuario final la lee. RLS lo niega todo salvo
-- a los roles con BYPASSRLS.
alter table public.media_reconcile_runs enable row level security;

-- =====================================================================================
-- 12) GRANTS — rol por rol. Una tabla nueva nace SIN permisos (default privileges de
--     `public` revocados); lo de abajo es la reconstrucción EXPLÍCITA de la lista auditada,
--     no una copia de lo que trajera el entorno. Se revoca todo primero y se concede
--     exactamente lo verificado, para que el resultado converja al mismo ACL sin importar
--     qué default privileges tuviera el entorno de partida (local del CLI nuevo: `Dxtm` para
--     service_role; producción antigua: `arwdDxtm` — ver skill rls-security punto 13).
-- =====================================================================================

-- --- anon: nada, en ninguna tabla de este esquema. La clave publicable va embebida en la
--     app; `anon` no necesita leer ni escribir directamente ninguna tabla de public. Origen:
--     20260809140854 + 20260809142046.
revoke all on all tables in schema public from anon;
alter default privileges in schema public revoke all on tables from anon;

-- --- authenticated: reset total y reconstrucción explícita.
revoke all on all tables in schema public from authenticated;
alter default privileges in schema public revoke all on tables from authenticated;

grant select on public.badges               to authenticated;
grant select on public.onboarding_responses to authenticated;
grant select on public.profiles             to authenticated;
grant select on public.profiles_private     to authenticated;
grant select on public.user_badges          to authenticated;
-- categories, experience_cases y user_experiences NO llevan grant para authenticated: el
-- cliente los lee vía Edge Function con service_role (onboarding-catalogs,
-- onboarding-complete), nunca por PostgREST directo, aunque sus policies sean públicas.

-- Escritura de columna, nunca de tabla (RLS filtra filas, el GRANT filtra columnas — hacen
-- falta los dos). `phone_number` salió de esta lista al borrarse la columna (20260816090000);
-- `photo_url` salió en 20260809140854 (un usuario podía escribir una URL arbitraria que
-- cargaba la app del resto: registro de IP e imágenes sin moderar).
grant update (display_name, language) on public.profiles to authenticated;
grant update (birth_date, gender, country) on public.profiles_private to authenticated;

-- --- service_role: BYPASSRLS, NO BYPASSGRANT — se le aplican los GRANT igual que a
--     cualquier rol no superusuario (comprobado, no supuesto: sin esto, TODAS las Edge
--     Functions responden 500 "permission denied for table X" en cualquier entorno nuevo).
--     No se acota por columna: el control de columna existe para impedir que el CLIENTE se
--     autoconceda level/xp/vip_status; service_role nunca viaja al cliente. Origen:
--     20260810093000 + 20260810160000 (normalización de defaults) + 20260810180000 +
--     20260812090000.
revoke insert, select, update, delete on all tables in schema public from service_role;
alter default privileges in schema public
  revoke insert, select, update, delete on tables from service_role;

grant select on public.categories       to service_role;
grant select on public.experience_cases to service_role;
grant select, insert, update on public.onboarding_responses to service_role;
grant select, insert, update, delete on public.user_experiences to service_role;
grant select, update on public.profiles         to service_role;
grant select, update on public.profiles_private to service_role;
grant insert on public.photo_audit_log to service_role;
grant select, insert, update on public.storage_gc_queue to service_role;
grant select, insert, update on public.media_reconcile_runs to service_role;
-- badges y user_badges quedan deliberadamente sin DML para service_role: hoy ninguna Edge
-- Function las escribe. Cuando `badge-award` exista, su migración concede lo suyo.

-- Grant de UNA SOLA COLUMNA, no de la tabla: service_role solo tiene INSERT sobre
-- photo_audit_log (la auditoría no se modifica ni se borra por código — la retención la
-- aplica el cron directo). `ops-digest-cron` necesita CONTAR filas fuera de plazo sin poder
-- leer user_id ni photo_path. Origen: 20260812090000.
--
-- ⚠️ Un `REVOKE SELECT` a nivel de TABLA retira también cualquier `SELECT` de COLUMNA sobre
-- esa misma tabla: no son privilegios independientes. Cualquier futuro
-- `revoke ... on all tables in schema public from service_role` tiene que reconceder esta
-- línea en la misma migración, o ops-digest-cron empieza a fallar con "permission denied for
-- table photo_audit_log" en la última consulta de su Promise.all — arrastrando consigo la
-- alerta, más urgente, de storage_gc_queue.status='failed'.
grant select (created_at) on public.photo_audit_log to service_role;

-- =====================================================================================
-- 13) FUNCIONES
-- =====================================================================================

-- Reutilizable por cualquier tabla futura con `updated_at`. No es `security definer`: no se
-- salta RLS ni necesita revocar EXECUTE (una función que devuelve `trigger` no es invocable
-- como RPC por PostgREST). Origen: 20260809000000.
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- Encola la foto para borrado en R2 cuando se borra el PERFIL (por sí solo o por cascada al
-- borrarse la cuenta). `set search_path = ''` endurece el linter `function_search_path_mutable`
-- sin cambiar el comportamiento: el cuerpo ya cualifica `public.storage_gc_queue`. SE
-- MANTIENE SECURITY INVOKER a propósito: el borrado real de cuenta lo ejecuta GoTrue
-- conectado como `supabase_auth_admin` (un rol SIN INSERT sobre la cola y SIN DELETE sobre
-- profiles), pero un DELETE en cascada por clave ajena corre con los privilegios del
-- PROPIETARIO de la tabla referenciante, no del rol invocante — comprobado ejecutando
-- `set role supabase_auth_admin; delete from auth.users ...`, no deducido. Ascenderla a
-- SECURITY DEFINER sería ampliar privilegios sin necesidad. Origen: 20260809104229 +
-- 20260810160000 (search_path).
-- Cuerpo textual idéntico al de 20260809104229 (comparación literal exigida por el ADR 0017:
-- pg_dump captura el código fuente de una función tal cual, así que hasta el estilo de
-- mayúsculas de SQL importa para la prueba de equivalencia).
create or replace function public.queue_profile_photo_for_deletion()
returns trigger
language plpgsql
set search_path = ''
as $$
BEGIN
  IF OLD.photo_path IS NOT NULL THEN
    INSERT INTO public.storage_gc_queue (user_id, photo_path, status)
    VALUES (OLD.user_id, OLD.photo_path, 'pending');
  END IF;
  RETURN OLD;
END;
$$;

-- Crea y RELLENA el perfil al darse de alta, validando en vez de copiar. El cliente Flutter
-- nunca inserta en profiles/profiles_private durante el alta: si lo hiciera, chocaría con
-- este trigger, o un fallo de red entre el alta y ese insert dejaría un usuario en
-- auth.users sin fila de perfil.
--
-- `raw_user_meta_data` LO ELIGE QUIEN LLAMA, no la app: la clave publicable va embebida en
-- el binario, así que un `curl` contra el endpoint de alta de GoTrue podía mandar el `data`
-- que quisiera y saltarse toda la validación del proyecto con solo registrarse (H-SV-03).
-- Hasta 20260816090000 esta función solo copiaba con `nullif(...,'')`; ahora valida:
--   - display_name ausente o en blanco → rechazado (2026-08-17, ADR 0018: antes pasaba, y la
--     constraint de longitud tampoco lo paraba porque un NULL satisface una CHECK).
--   - display_name > 60 caracteres → rechazado (la ve TODO EL MUNDO, profiles_read_public
--     es `using (true)`).
--   - gender fuera de ('hombre','mujer','otro') → rechazado (la columna es `text` sin enum
--     de Postgres; sin esto el único límite era `profile-update`, el camino que un atacante
--     no usa).
--   - birth_date no parseable → rechazado con check_violation (23514) legible, no con el
--     `invalid_datetime_format` (22007) crudo del cast, que tumbaba el INSERT en auth.users
--     entero y devolvía un 500 opaco.
--   - edad < 13 años → rechazado (Art. 8 RGPD: barrera de consentimiento que antes solo se
--     aplicaba al EDITAR el perfil, nunca al crearlo — el único sitio donde tiene sentido).
--   - edad > 120 años → rechazado.
--
-- `security definer` + `set search_path = public` son imprescindibles: durante el signup no
-- hay sesión (auth.uid() es NULL), así que las policies de arriba rechazarían el insert;
-- `security definer` corre con los privilegios del propietario y se salta RLS igual que
-- service_role. Fijar `search_path` evita que una referencia sin cualificar a `profiles`
-- resuelva a una tabla atacante inyectada en el search_path del rol. Origen: 20260808000000
-- + 20260816090000 (validación).
-- ⚠️ El cuerpo YA NO es textualmente idéntico al de 20260816090000: el 2026-08-17 se añadió el
-- rechazo del nombre ausente y el `btrim` (ADR 0018). La prueba de equivalencia del ADR 0017
-- describe este fichero en el commit del squash, no su estado actual — ver la enmienda al final
-- de ese ADR. Los comentarios de dentro del `$$ ... $$` siguen siendo parte del código fuente
-- que pg_dump reproduce literalmente, así que cualquier reescritura futura cuenta como cambio.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  meta jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
  -- `btrim` antes del `nullif`: así '   ' se convierte en NULL y cae en el rechazo de abajo,
  -- y el nombre llega a `profiles` ya recortado, igual que lo deja `profile-update`.
  v_display_name text := nullif(btrim(meta->>'display_name'), '');
  v_gender text := nullif(meta->>'gender', '');
  v_birth_date_raw text := nullif(meta->>'birth_date', '');
  v_birth_date date;
begin
  -- `raw_user_meta_data` lo elige QUIEN LLAMA, no la app: la clave publicable va embebida en el
  -- binario, así que cualquiera puede mandar el `data` que quiera al endpoint de alta de GoTrue.
  -- Todo lo que salga de aquí se trata como entrada hostil.

  -- Obligatorio desde el 2026-08-17 (ADR 0018). Sin esto el alta creaba perfiles sin nombre:
  -- la constraint de longitud los dejaba pasar por ser NULL. Se rechaza aquí, y no solo en la
  -- constraint, para que el error diga QUÉ campo falta en vez de citar un nombre de constraint.
  if v_display_name is null then
    raise exception 'display_name es obligatorio'
      using errcode = 'check_violation';
  end if;

  if char_length(v_display_name) > 60 then
    raise exception 'display_name excede 60 caracteres'
      using errcode = 'check_violation';
  end if;

  if v_gender is not null and v_gender not in ('hombre', 'mujer', 'otro') then
    raise exception 'gender no es un valor admitido'
      using errcode = 'check_violation';
  end if;

  if v_birth_date_raw is not null then
    -- Se parsea con manejo de error en vez de dejar que el cast reviente: un `::date` sobre basura
    -- lanzaba `invalid_datetime_format` DENTRO del trigger y tumbaba el INSERT en auth.users, así
    -- que el alta devolvía un 500 opaco en lugar de decir qué campo estaba mal.
    begin
      v_birth_date := v_birth_date_raw::date;
    exception when others then
      raise exception 'birth_date debe tener formato YYYY-MM-DD'
        using errcode = 'check_violation';
    end;

    -- Art. 8 RGPD: por debajo de 13 años no hay consentimiento válido. Es la barrera que faltaba en
    -- el único camino por el que se crean cuentas.
    if v_birth_date > current_date - interval '13 years' then
      raise exception 'birth_date implica una edad menor de 13 anios'
        using errcode = 'check_violation';
    end if;

    if v_birth_date < current_date - interval '120 years' then
      raise exception 'birth_date implica una edad fuera de rango'
        using errcode = 'check_violation';
    end if;
  end if;

  insert into public.profiles (user_id, display_name)
  values (new.id, v_display_name)
  on conflict (user_id) do nothing;

  insert into public.profiles_private (user_id, birth_date, gender)
  values (new.id, v_birth_date, v_gender)
  on conflict (user_id) do nothing;

  return new;
end;
$$;

-- `security definer` + expuesta por PostgREST como `POST /rest/v1/rpc/handle_new_user` sería
-- ejecutable por anon/authenticated (lint `anon_security_definer_function_executable`) si no
-- se revoca. El trigger sigue disparando sin este privilegio: Postgres no comprueba EXECUTE
-- del invocador al ejecutar una función de trigger (verificado con un alta real). Se repite
-- tras cada `create or replace` aunque este preserve los grants existentes, para que quien
-- lea esta migración suelta no tenga que ir a comprobarlo. Origen: 20260808000000.
revoke execute on function public.handle_new_user() from public, anon, authenticated;

-- =====================================================================================
-- 14) TRIGGERS
-- =====================================================================================

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row
  execute function public.handle_new_user();

drop trigger if exists onboarding_responses_set_updated_at on public.onboarding_responses;
create trigger onboarding_responses_set_updated_at
  before update on public.onboarding_responses
  for each row
  execute function public.set_updated_at();

drop trigger if exists profiles_on_delete_queue_photo on public.profiles;
create trigger profiles_on_delete_queue_photo
  before delete on public.profiles
  for each row
  execute function public.queue_profile_photo_for_deletion();

-- ROLLBACK:
-- drop trigger if exists profiles_on_delete_queue_photo on public.profiles;
-- drop trigger if exists onboarding_responses_set_updated_at on public.onboarding_responses;
-- drop trigger if exists on_auth_user_created on auth.users;
-- drop function if exists public.handle_new_user();
-- drop function if exists public.queue_profile_photo_for_deletion();
-- drop function if exists public.set_updated_at();
-- drop table if exists public.media_reconcile_runs;
-- drop table if exists public.photo_audit_log;
-- drop table if exists public.storage_gc_queue;
-- drop table if exists public.user_experiences;
-- drop table if exists public.experience_cases;
-- drop table if exists public.user_badges;
-- drop table if exists public.badges;
-- drop table if exists public.onboarding_responses;
-- drop table if exists public.profiles_private;
-- drop table if exists public.profiles;
-- drop table if exists public.categories;
-- (los grants desaparecen solos al borrar las tablas; los default privileges revocados se
-- restauran con `alter default privileges in schema public grant all on tables to anon,
-- authenticated;` si de verdad se quiere volver al modelo "todo abierto, RLS decide" —
-- no se recomienda, ver CLAUDE.md.)
