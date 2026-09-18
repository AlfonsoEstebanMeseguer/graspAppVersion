-- Baseline consolidado: sustituye a las 4 migraciones de crons del historial 20260810..20260812
-- (schedule_media_gc_cron, use_dedicated_token_for_internal_cron, schedule_reconcile_and_digest_crons,
-- add_photo_audit_retention). Tabla de correspondencia completa:
-- apps/backend/supabase/migrations/README.md. Decisión y prueba de equivalencia:
-- docs/decisions/0017-consolidar-las-migraciones-en-tres.md.
--
-- IDEMPOTENTE a propósito: `create extension if not exists`, `create schema if not exists`,
-- `create or replace function`, y `cron.schedule` hace upsert por nombre (reaplicar
-- reprograma, no duplica).
--
-- Depende de 20260816120000_baseline_schema.sql (usa public.photo_audit_log).

-- =====================================================================================
-- 1) EXTENSIONES
-- =====================================================================================
-- pg_cron crea su propio esquema `cron`; pg_net expone `net.*` aunque la extensión se
-- instale en `extensions` (así está ya en local y en producción).
create extension if not exists pg_cron;
create extension if not exists pg_net with schema extensions;

-- =====================================================================================
-- 2) ESQUEMA PRIVADO — fuera del alcance de PostgREST
-- =====================================================================================
-- Cualquier función de `public` la expone PostgREST como `POST /rest/v1/rpc/<nombre>`. Los
-- envoltorios de abajo son SECURITY DEFINER y leen Vault: exponerlos sería regalar un
-- disparador de cada cron. `private` no está en `api.schemas`, así que PostgREST no lo ve.
create schema if not exists private;

revoke all on schema private from public;
revoke all on schema private from anon;
revoke all on schema private from authenticated;
revoke all on schema private from service_role;

-- =====================================================================================
-- 3) TOKEN DEDICADO EN VAULT — uno por entorno, generado por la base de datos
-- =====================================================================================
-- Por qué NO se autentican los crons con la `service_role key`: `verify_jwt` solo comprueba
-- que el token esté firmado por el proyecto, y la `anon key` (embebida en la app) también lo
-- cumple. Y `SUPABASE_SERVICE_ROLE_KEY` tampoco vale como comparación: su CONTENIDO lo decide
-- la plataforma y cambia sin avisar (el 2026-08-10 Supabase pasó de inyectar el JWT legado
-- `eyJ…` a una clave `sb_secret_…`, y el cron empezó a devolver 401 sin que nadie tocara el
-- código). Además, mandar una credencial de acceso total a la base de datos por HTTP cada
-- pocos minutos es radio de impacto innecesario.
--
-- La función NO conoce el token: conoce su SHA-256 (`INTERNAL_CRON_TOKEN_SHA256`, publicado
-- como secreto de las Edge Functions). El hash no sirve para autenticarse, así que puede
-- pegarse en el panel sin riesgo — el secreto no viaja nunca fuera de Vault. Radio de impacto
-- si aun así se filtrase el hash: nada, porque un hash no autentica. Si se filtrase el token:
-- alguien puede disparar el cron, nada más. Solo se crea si no existe: regenerarlo invalidaría
-- el hash ya publicado y dejaría el cron en 401 hasta republicarlo.
do $$
begin
  if not exists (select 1 from vault.secrets where name = 'internal_cron_token') then
    perform vault.create_secret(
      encode(extensions.gen_random_bytes(32), 'hex'),
      'internal_cron_token',
      'Token dedicado para invocar funciones internas (media-gc-cron, media-reconcile-cron, '
      'ops-digest-cron). La función solo conoce su SHA-256.'
    );
  end if;
end $$;

-- Limpieza defensiva: un entorno reconciliado desde el historial viejo (antes de
-- 20260810170000) puede conservar el secreto `service_role_key` que ya no usa nadie. Un
-- secreto guardado que ningún código lee es superficie de ataque sin contrapartida.
delete from vault.secrets where name = 'service_role_key';

-- =====================================================================================
-- 4) ENVOLTORIOS — cada uno lee Vault, falla ruidoso si faltan secretos, e invoca su Edge
--    Function con el token dedicado en el Authorization.
-- =====================================================================================
-- `search_path = ''` obliga a cualificar cada objeto y evita que un esquema inyectado en el
-- search_path del invocador secuestre una función SECURITY DEFINER.
--
-- SETUP OBLIGATORIO POR ENTORNO (esta migración NO crea `project_url`, ni debe: los secretos
-- no viajan en migraciones). Una sola vez, desde el SQL Editor del panel (producción) o con
-- `apps/backend/scripts/setup-cron-secrets.ps1` (local):
--
--     select vault.create_secret('https://<ref>.supabase.co', 'project_url');
--
-- Y publicar el HASH (no el token) como secreto de las Edge Functions:
--
--     select encode(extensions.digest(decrypted_secret, 'sha256'), 'hex')
--       from vault.decrypted_secrets where name = 'internal_cron_token';
--     supabase secrets set INTERNAL_CRON_TOKEN_SHA256=<hash>
--
-- Mientras falte cualquiera de los dos, el envoltorio deja un WARNING en
-- `cron.job_run_details` y no dispara ningún POST contra NULL:
--
--     select status, return_message, start_time from cron.job_run_details
--      where jobid = (select jobid from cron.job where jobname = 'media-gc-cron')
--      order by start_time desc limit 5;

create or replace function private.invoke_media_gc_cron()
returns bigint
language plpgsql
security definer -- Ejecuta con privilegios de quien la creó
set search_path = ''
as $$
declare
  v_project_url text;
  v_token       text;
  v_request_id  bigint;
begin
  select decrypted_secret into v_project_url
    from vault.decrypted_secrets where name = 'project_url';

  select decrypted_secret into v_token
    from vault.decrypted_secrets where name = 'internal_cron_token';

  -- Falla ruidosa y explícita. Sin esto, `net.http_post(url := null)` produce un error
  -- opaco cada 5 minutos y nadie se entera de que el GC lleva meses sin correr.
  if v_project_url is null or v_token is null then
    raise warning
      'media-gc-cron no se ha invocado: faltan secretos en Vault (project_url=%, internal_cron_token=%). Ver la cabecera de 20260810170000_use_dedicated_token_for_internal_cron.sql.',
      v_project_url is not null, v_token is not null;
    return null;
  end if;

  select net.http_post(
    url     := v_project_url || '/functions/v1/media-gc-cron',
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      -- El token NO es un JWT, por eso `media-gc-cron` lleva verify_jwt = false en
      -- config.toml: con la verificación activa el gateway lo rechazaría antes de que
      -- `requireInternalCaller` llegase a ejecutarse.
      'Authorization', 'Bearer ' || v_token
    ),
    body    := jsonb_build_object('invoked_at', now()),
    timeout_milliseconds := 30000
  ) into v_request_id;

  return v_request_id;
end;
$$;

revoke all on function private.invoke_media_gc_cron() from public;
revoke all on function private.invoke_media_gc_cron() from anon;
revoke all on function private.invoke_media_gc_cron() from authenticated;
revoke all on function private.invoke_media_gc_cron() from service_role;

create or replace function private.invoke_media_reconcile_cron()
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_project_url text;
  v_token       text;
  v_request_id  bigint;
begin
  select decrypted_secret into v_project_url
    from vault.decrypted_secrets where name = 'project_url';

  select decrypted_secret into v_token
    from vault.decrypted_secrets where name = 'internal_cron_token';

  -- Falla ruidosa: sin esto, net.http_post(url := null) deja un error opaco a diario y nadie se
  -- entera de que el barrido lleva meses sin correr.
  if v_project_url is null or v_token is null then
    raise warning
      'media-reconcile-cron no se ha invocado: faltan secretos en Vault (project_url=%, internal_cron_token=%).',
      v_project_url is not null, v_token is not null;
    return null;
  end if;

  select net.http_post(
    url     := v_project_url || '/functions/v1/media-reconcile-cron',
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'Authorization', 'Bearer ' || v_token
    ),
    body    := jsonb_build_object('invoked_at', now()),
    -- Listar el bucket entero es más lento que drenar la cola: 60 s en vez de los 30 del GC.
    timeout_milliseconds := 60000
  ) into v_request_id;

  return v_request_id;
end;
$$;

revoke all on function private.invoke_media_reconcile_cron() from public;
revoke all on function private.invoke_media_reconcile_cron() from anon;
revoke all on function private.invoke_media_reconcile_cron() from authenticated;
revoke all on function private.invoke_media_reconcile_cron() from service_role;

create or replace function private.invoke_ops_digest_cron()
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_project_url text;
  v_token       text;
  v_request_id  bigint;
begin
  select decrypted_secret into v_project_url
    from vault.decrypted_secrets where name = 'project_url';

  select decrypted_secret into v_token
    from vault.decrypted_secrets where name = 'internal_cron_token';

  if v_project_url is null or v_token is null then
    raise warning
      'ops-digest-cron no se ha invocado: faltan secretos en Vault (project_url=%, internal_cron_token=%).',
      v_project_url is not null, v_token is not null;
    return null;
  end if;

  select net.http_post(
    url     := v_project_url || '/functions/v1/ops-digest-cron',
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'Authorization', 'Bearer ' || v_token
    ),
    body    := jsonb_build_object('invoked_at', now()),
    timeout_milliseconds := 30000
  ) into v_request_id;

  return v_request_id;
end;
$$;

revoke all on function private.invoke_ops_digest_cron() from public;
revoke all on function private.invoke_ops_digest_cron() from anon;
revoke all on function private.invoke_ops_digest_cron() from authenticated;
revoke all on function private.invoke_ops_digest_cron() from service_role;

-- =====================================================================================
-- 5) PROGRAMACIÓN — 4 jobs. `cron.schedule` hace upsert por nombre.
-- =====================================================================================
-- Cada 5 min: la inmensa mayoría de ejecuciones no encuentran nada pendiente y salen en un
-- par de milisegundos; el coste es despreciable frente a acortar la ventana en la que una
-- foto borrada sigue viva en R2.
select cron.schedule(
  'media-gc-cron',
  '*/5 * * * *',
  $$select private.invoke_media_gc_cron();$$
);

-- 03:00 UTC el barrido de huérfanos, 08:00 UTC el digest: cinco horas de separación para que
-- el correo de cada mañana refleje el barrido de esa madrugada, no el de la anterior.
select cron.schedule(
  'media-reconcile-cron',
  '0 3 * * *',
  $$select private.invoke_media_reconcile_cron();$$
);

select cron.schedule(
  'ops-digest-cron',
  '0 8 * * *',
  $$select private.invoke_ops_digest_cron();$$
);

-- 04:00 UTC, entre el barrido (03:00) y el digest (08:00), para que el correo de cada mañana
-- refleje el estado ya purgado de ese mismo día. Es un DELETE directo, sin envoltorio: el
-- comando de un cron se guarda en texto plano en `cron.job.command`, y este comando no lleva
-- ningún secreto que proteger — un envoltorio no protegería nada, solo añadiría una función
-- más que mantener. Tampoco hace falta `grant delete`: `cron.schedule` ejecuta el job como el
-- rol que lo programó (el que aplica esta migración), que ya es dueño de la tabla.
--
-- PUNTERO INVERSO: si cambia el intervalo de 90 días de aquí, cambian también
-- `AUDIT_RETENTION_DAYS` y `AUDIT_STALE_DAYS` (91, el margen de un día) en
-- `_shared/digest.ts` — los tres números se mueven juntos o el digest empieza a alertar cada
-- mañana sobre un sistema sano. El grant que necesita `ops-digest-cron` para poder CONTAR
-- estas filas (`select (created_at) on public.photo_audit_log`) vive en
-- 20260816120000_baseline_schema.sql, junto al resto de grants de esa tabla.
select cron.schedule(
  'photo-audit-retention',
  '0 4 * * *',
  $$delete from public.photo_audit_log where created_at < now() - interval '90 days'$$
);

-- ROLLBACK:
-- select cron.unschedule('photo-audit-retention');
-- select cron.unschedule('ops-digest-cron');
-- select cron.unschedule('media-reconcile-cron');
-- select cron.unschedule('media-gc-cron');
-- drop function if exists private.invoke_ops_digest_cron();
-- drop function if exists private.invoke_media_reconcile_cron();
-- drop function if exists private.invoke_media_gc_cron();
-- delete from vault.secrets where name = 'internal_cron_token';
-- drop schema if exists private;
-- -- Las extensiones NO se eliminan en el rollback: pueden tener otros consumidores.
