-- =================================================================================================
-- Fase 4 · Tarea 5 — Las tres tablas de Conectar y su purga.
--
-- Plan: docs/superpowers/plans/2026-08-23-contactos-y-mensajeria.md (Tarea 5)
-- Spec: docs/spec-contactos-mensajes-conectar.md (§2.7, RN-46, RN-47, RN-48)
--
-- Las tres son de USO EXCLUSIVO de `connect-feed` (Tarea 16) con `service_role`. Ningún cliente las
-- lee ni las escribe, así que no llevan ni policies ni grants para `authenticated`: RLS activo y
-- deny by default (punto 6b de db-schema — la regla por defecto es NO conceder nada).
--
-- Las tres evitan lógica de caducidad en el código metiéndola en la FORMA de la clave primaria,
-- que es lo que hace que no haya nada que recordar mantener.
-- =================================================================================================

-- =================================================================================================
-- 1) `connect_dismissals` — "No mostrar más"
-- =================================================================================================

-- RN-48: los rechazos NO CADUCAN NUNCA. Por eso esta tabla no tiene ninguna columna de fecha: no
-- habría nadie que la leyera, y una columna que nadie lee es una promesa falsa en el esquema
-- (punto 8 de db-schema). Es también la razón de que no entre en la purga de abajo.
create table if not exists public.connect_dismissals (
  user_id           uuid not null references public.profiles(user_id) on delete cascade,
  dismissed_user_id uuid not null references public.profiles(user_id) on delete cascade,
  primary key (user_id, dismissed_user_id),
  constraint connect_dismissals_no_self check (user_id <> dismissed_user_id)
);

comment on table public.connect_dismissals is
  'RN-48: a quien el usuario ha dicho "No mostrar mas" en Conectar. No caduca nunca, de ahi que no '
  'tenga columna de fecha y que la purga diaria no la toque. La puerta de entrada es la accion '
  'discreta de la tarjeta (decision 8 del plan): un mecanismo sin pantalla que lo dispare no existe.';

-- =================================================================================================
-- 2) `connect_impressions` — a quién se le ha enseñado hoy
-- =================================================================================================

-- RN-46 EN UNA SOLA FORMA: con la fecha DENTRO de la clave primaria, reponer a alguien hoy es
-- imposible y mañana es automático. No hay ninguna lógica de caducidad que escribir ni que
-- acordarse de mantener; el calendario la hace sola.
create table if not exists public.connect_impressions (
  user_id       uuid not null references public.profiles(user_id) on delete cascade,
  shown_user_id uuid not null references public.profiles(user_id) on delete cascade,
  shown_on      date not null default current_date,
  primary key (user_id, shown_user_id, shown_on)
);

-- La PK empieza por `user_id`, así que la purga —que filtra SOLO por fecha— no la puede usar. Sin
-- este índice el barrido diario haría un seq scan que crece con el histórico entero.
create index if not exists connect_impressions_shown_on_idx
  on public.connect_impressions (shown_on);

-- =================================================================================================
-- 3) `connect_feed_runs` — el tope de 5 pull-to-refresh al día
-- =================================================================================================
create table if not exists public.connect_feed_runs (
  user_id       uuid not null references public.profiles(user_id) on delete cascade,
  ran_on        date not null default current_date,
  refresh_count int  not null default 0 check (refresh_count >= 0),
  primary key (user_id, ran_on)
);

create index if not exists connect_feed_runs_ran_on_idx
  on public.connect_feed_runs (ran_on);

comment on table public.connect_feed_runs is
  'RN-46: tope de 5 pull-to-refresh diarios. La fecha va en la PK, asi que el contador se reinicia '
  'solo cada dia sin ningun trabajo programado. La purga de 7 dias es higiene, no correccion: la '
  'fila de ayer ya no cuenta para el tope de hoy aunque siga ahi.';

-- =================================================================================================
-- 4) RLS — activo y SIN POLICIES en las tres. Deny by default.
-- =================================================================================================
-- Ningún cliente toca estas tablas: las lee y las escribe `connect-feed` con `service_role`, que
-- tiene BYPASSRLS. Sin policies, cualquier consulta con el JWT de un usuario devuelve cero filas
-- (y sin grant, ni siquiera llega a evaluarse la policy: falla antes, en el privilegio).
alter table public.connect_dismissals  enable row level security;
alter table public.connect_impressions enable row level security;
alter table public.connect_feed_runs   enable row level security;

-- =================================================================================================
-- 5) GRANTS — LOS TRES ROLES (puntos 11 y 12 de rls-security)
-- =================================================================================================

-- --- anon y authenticated: NADA en las tres. Son tablas nuevas, así que nacen sin permisos (punto
--     6b de db-schema) y no hace falta ningún `revoke`: basta con no conceder.
--
--     Merece decirlo explícitamente porque es tentador conceder `select` de `connect_dismissals`
--     "para que el usuario vea a quién ha ocultado": esa pantalla NO EXISTE (no está en la spec), y
--     una tabla que nadie lee no lleva grant. Cuando exista, su migración lo concederá.

-- --- service_role: DML completo en las tres. Sin esto, `connect-feed` responde 500
--     "permission denied for table X" en cualquier entorno creado desde cero — `service_role` tiene
--     BYPASSRLS pero NO BYPASSGRANT (punto 12 de rls-security).
grant select, insert, update, delete on public.connect_dismissals  to service_role;
grant select, insert, update, delete on public.connect_impressions to service_role;
grant select, insert, update, delete on public.connect_feed_runs   to service_role;

-- =================================================================================================
-- 6) PURGA — `pg_cron` DESDE ESTA MIGRACIÓN, NUNCA DESDE `config.toml`
-- =================================================================================================
-- Punto 11b de db-schema: el CLI de Supabase no tiene clave `schedule` para las funciones.
-- `supabase start` la IGNORA EN SILENCIO y `db reset` aborta con `has invalid keys: schedule`. Un
-- cron declarado allí no existe en ningún entorno, y el fallo es mudo. Precedente propio: el cron
-- de RGPD estuvo declarado en `config.toml` durante todo el Bloque 3 sin existir.

create extension if not exists pg_cron;

-- `private` ya lo crea `20260816120001_baseline_crons.sql`; se repite `if not exists` para que esta
-- migración no dependa del orden de aplicación de aquella.
create schema if not exists private;
revoke all on schema private from public, anon, authenticated, service_role;

-- Envoltorio en `private`, NO en `public`: en `public` PostgREST lo expondría como
-- `POST /rest/v1/rpc/purge_connect_tables` y sería un disparador público de un job interno
-- (punto 11 de db-schema). `private` no está en `api.schemas`, así que PostgREST no lo ve.
--
-- `security invoker` (el defecto) a propósito: `cron.schedule` ejecuta el job como el rol que lo
-- programó —el que aplica esta migración—, que ya es dueño de las tablas y por tanto se salta su
-- RLS. Ascenderlo a `definer` sería ampliar privilegios para resolver un problema que no existe
-- (punto 14 de rls-security). Comprobado ejecutándolo, no supuesto.
--
-- Devuelve el número de filas borradas para que la ejecución no sea muda: `cron.job_run_details`
-- guarda el mensaje de retorno, así que un barrido que deje de borrar se puede ver ahí.
create or replace function private.purge_connect_tables()
returns text
language plpgsql
set search_path = ''
as $$
declare
  v_impressions int;
  v_runs        int;
begin
  delete from public.connect_impressions where shown_on < current_date - 7;
  get diagnostics v_impressions = row_count;

  delete from public.connect_feed_runs where ran_on < current_date - 7;
  get diagnostics v_runs = row_count;

  -- `connect_dismissals` NO se purga: RN-48 dice que un "No mostrar mas" no caduca nunca.
  return format('connect purge: %s impressions, %s feed_runs', v_impressions, v_runs);
end;
$$;

revoke all on function private.purge_connect_tables() from public, anon, authenticated, service_role;

-- 04:30 UTC: después de `photo-audit-retention` (04:00) y antes del digest (08:00), para que el
-- correo de cada mañana refleje el estado ya purgado de ese mismo día.
-- `cron.schedule` hace UPSERT por nombre, así que reaplicar esta migración reprograma en vez de
-- duplicar el job.
select cron.schedule(
  'connect-purge',
  '30 4 * * *',
  $$select private.purge_connect_tables();$$
);

-- =================================================================================================
-- VERIFICACIÓN POSTERIOR — y aquí NO basta con que la migración aplique
-- =================================================================================================
-- Que el job aparezca programado NO prueba que funcione: un nombre de función mal escrito se
-- programa igual de bien y falla en silencio cada madrugada. Las tres comprobaciones, en orden de
-- lo que de verdad demuestran:
--
--   -- 1) Que existe y está activo:
--   select jobname, schedule, active from cron.job where jobname = 'connect-purge';
--
--   -- 2) Que EL COMANDO GUARDADO es ejecutable — esto es lo que caza el nombre mal escrito.
--   --    Se ejecuta literalmente lo que hay en cron.job.command, no una copia a mano:
--   select command from cron.job where jobname = 'connect-purge';  \gexec
--
--   -- 3) Que además BORRA lo que debe y respeta lo que no:
--   --    apps/backend/supabase/tests/connect-purge.sql
--
--   -- Y tras una ejecución real, el estado (`succeeded` solo dice que el SQL corrió):
--   select status, return_message, start_time from cron.job_run_details
--    where jobid = (select jobid from cron.job where jobname = 'connect-purge')
--    order by start_time desc limit 5;

-- =================================================================================================
-- ROLLBACK:
-- =================================================================================================
-- select cron.unschedule('connect-purge');
-- drop function if exists private.purge_connect_tables();
-- revoke select, insert, update, delete on public.connect_feed_runs   from service_role;
-- revoke select, insert, update, delete on public.connect_impressions from service_role;
-- revoke select, insert, update, delete on public.connect_dismissals  from service_role;
-- drop table if exists public.connect_feed_runs;
-- drop table if exists public.connect_impressions;
-- drop table if exists public.connect_dismissals;
-- -- `private` y pg_cron NO se eliminan: tienen otros consumidores (baseline_crons).
