-- Salas de voz (Fase 5, Tarea 5): ciclo de vida — lo que cierra las salas muertas sin que nadie
-- intervenga. Depende de 20260901120000_rooms.sql (tablas `rooms`/`room_participants`/
-- `room_messages`, funciones de escritura de room-actions) y de 20260816120001_baseline_crons.sql
-- (`private` schema, token dedicado en Vault, patrón `private.invoke_*_cron`).
--
-- =====================================================================================
-- 1) LOS MENSAJES DE UNA SALA SE BORRAN CUANDO LA SALA TERMINA — §3.1 de la spec
-- =====================================================================================
-- El plan original dejaba esto en manos de `on delete cascade` sobre `room_messages.room_id`, y
-- eso NO funciona: `rooms` nunca se BORRA, se marca `status = 'ended'` (la fila se queda, porque
-- `ended_reason` es trazabilidad) — así que esa cascada jamás se dispara y los mensajes
-- sobreviven indefinidamente. Hueco anotado en el plan, resuelto aquí. Decisión del 2026-08-31,
-- documentada en el brief de esta tarea (no en un ADR aparte: es un detalle de implementación de
-- una regla que la spec ya fijaba, no un cambio de regla).
--
-- El borrado va en un TRIGGER sobre el paso de `status` a 'ended', no dentro del cron. Motivo: una
-- sala muere por TRES caminos distintos —
--   (a) `room-lifecycle-cron` / `room_lifecycle_sweep` (este fichero, más abajo),
--   (b) `room_leave` cuando se va el host (`ended_reason = 'host_left'`),
--   (c) `room_end` (`ended_reason = 'host_ended'`)
-- — y las tres funciones de (b) y (c) ya existen, selladas, en 20260901120000_rooms.sql. Si el
-- borrado viviera dentro de un solo camino (el cron), los otros dos dejarían mensajes huérfanos:
-- exactamente el fallo que este diseño evita. Un trigger sobre `rooms` cubre los tres caminos por
-- construcción, sin tocar ninguna de las funciones ya revisadas de la Tarea 3.
create or replace function public.room_messages_purge_on_end()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  -- `when` en la definición del trigger (más abajo) ya filtra la transición live->ended; esta
  -- comprobación es defensiva por si algún día se quita esa cláusula sin leer este comentario.
  if new.status = 'ended' and old.status = 'live' then
    delete from room_messages where room_id = new.id;
  end if;
  return new;
end $$;

-- Por defecto `create function` concede EXECUTE a PUBLIC. Un trigger no lo necesita para
-- dispararse (el sistema de triggers no comprueba EXECUTE sobre la función de disparo), pero
-- dejarlo abierto lo expondría igual como RPC (`POST /rest/v1/rpc/room_messages_purge_on_end`) —
-- mismo patrón que `room_max_occupants()`/`room_max_speakers()` en la migración anterior.
revoke all on function public.room_messages_purge_on_end() from public, anon, authenticated;

drop trigger if exists room_messages_purge_on_end_trg on public.rooms;
create trigger room_messages_purge_on_end_trg
  after update on public.rooms
  for each row
  when (new.status = 'ended' and old.status = 'live')
  execute function public.room_messages_purge_on_end();

-- =====================================================================================
-- 2) EL BARRIDO — cierra por: 2h alcanzadas ('expired'), vacía 10 min ('empty'), sin
--    actividad 10 min ('idle'). El freno ACOTA, no aborta (ver más abajo).
-- =====================================================================================
-- CUIDADO CON EL RELOJ DE "VACÍA 10 MINUTOS": una sala recién creada sin participantes no lleva
-- diez minutos vacía. La versión ingenua de esta condición —`not exists (participantes vivos)`,
-- sin más— no tiene reloj: dispara en el mismo instante en que la sala se queda sin nadie, y
-- cerraría salas que acaban de nacer antes de que a nadie le dé tiempo a entrar (comprobado con el
-- caso "sala E" de `rooms-lifecycle.sql`: una sala vaciada hace 1 minuto sigue viva tras el
-- barrido). Por eso "empty" usa `coalesce(max(left_at) de sus participantes, created_at)` como el
-- instante en que la sala se quedó vacía — si nunca tuvo participantes (o el último se fue antes
-- de que existiera esa fila), cae al `created_at` de la sala, no a `now()`. "idle" sigue la regla
-- original: `last_activity_at`, que SÍ tiene reloj propio porque `room_join`/`room_grant_speak`/
-- `room_revoke_speak` lo actualizan en su propia transacción (Tarea 3).
--
-- El freno ACOTA, no aborta. El disparador —crear salas— lo controla cualquier cuenta: un freno
-- que aborta al ver más de lo esperado es un interruptor de apagado regalado, y el estado es
-- absorbente porque nadie lo rearma (nadie reintenta un cron fallido a mano). Se procesa el tope
-- (`limit p_limit`, las más antiguas primero) y se marca la pasada con `capped = true`; la próxima
-- ejecución (un minuto después) recoge el resto.
create or replace function public.room_lifecycle_sweep(p_limit int default 200)
returns table (closed int, capped boolean)
language plpgsql security definer set search_path = public as $$
declare
  v_ids uuid[];
  v_closed int;
begin
  with candidates as (
    select r.id, r.created_at,
           exists (select 1 from room_participants p
                    where p.room_id = r.id and p.left_at is null) as has_live,
           coalesce(
             (select max(p.left_at) from room_participants p where p.room_id = r.id),
             r.created_at
           ) as empty_since,
           r.last_activity_at
      from rooms r
     where r.status = 'live'
  )
  select array_agg(id) into v_ids from (
    select id from candidates
     where created_at < now() - interval '2 hours'
        or (not has_live and empty_since < now() - interval '10 minutes')
        or (has_live and last_activity_at < now() - interval '10 minutes')
     order by created_at
     limit p_limit
  ) s;

  if v_ids is null then
    return query select 0, false;
    return;
  end if;

  update rooms r set status = 'ended', ended_at = now(), ended_reason = case
      when r.created_at < now() - interval '2 hours' then 'expired'
      when not exists (select 1 from room_participants p
                        where p.room_id = r.id and p.left_at is null) then 'empty'
      else 'idle'
    end
   where r.id = any(v_ids);

  update room_participants set left_at = now()
   where room_id = any(v_ids) and left_at is null;

  v_closed := array_length(v_ids, 1);
  return query select v_closed, v_closed >= p_limit;
end $$;

-- Mismo patrón de las siete funciones de escritura de room-actions: `revoke all ... from public,
-- anon, authenticated` también le retira a `service_role` el EXECUTE que tenía por ser miembro
-- implícito de PUBLIC (BYPASSRLS no es BYPASSGRANT, punto 12 de rls-security) — sin el `grant`
-- explícito de abajo, `room-lifecycle-cron` (que llama con `getServiceRoleClient()`) devolvería
-- "permission denied for function" en cualquier entorno nuevo.
revoke all on function public.room_lifecycle_sweep(int) from public, anon, authenticated;
grant execute on function public.room_lifecycle_sweep(int) to service_role;

-- =====================================================================================
-- 3) EL CRON — programado con `pg_cron` desde ESTA migración, nunca desde `config.toml` (esa
--    clave la ignora el CLI en silencio: un cron declarado ahí no existe en ningún entorno).
-- =====================================================================================
-- Se invoca la Edge Function `room-lifecycle-cron`, NO se llama a `room_lifecycle_sweep`
-- directamente desde `cron.schedule` — mismo patrón que `media-gc-cron`/`media-reconcile-cron`/
-- `ops-digest-cron` en `baseline_crons.sql`, y exigido por las restricciones globales de esta
-- tarea: "la Edge Function se autentica con `requireInternalCaller`", no con `verify_jwt` (lo
-- cumple la `anon key`, embebida en la app) ni con la clave de servicio. Si el cron llamara al RPC
-- directamente, la Edge Function y su `requireInternalCaller` quedarían sin ningún disparador real
-- — un mecanismo sin puerta de entrada, la misma clase de fallo que `account-delete` antes del ADR
-- 0016 (CLAUDE.md § Principios generales).
create or replace function private.invoke_room_lifecycle_cron()
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
      'room-lifecycle-cron no se ha invocado: faltan secretos en Vault (project_url=%, internal_cron_token=%). Ver 20260816120001_baseline_crons.sql § 3.',
      v_project_url is not null, v_token is not null;
    return null;
  end if;

  select net.http_post(
    url     := v_project_url || '/functions/v1/room-lifecycle-cron',
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

revoke all on function private.invoke_room_lifecycle_cron() from public;
revoke all on function private.invoke_room_lifecycle_cron() from anon;
revoke all on function private.invoke_room_lifecycle_cron() from authenticated;
revoke all on function private.invoke_room_lifecycle_cron() from service_role;

-- Cada minuto: una sala puede pasar de 'idle' a cerrada hasta un minuto tarde en el peor caso, y
-- es el intervalo que pide la Sección 11 del documento maestro para este cron. `cron.schedule`
-- hace upsert por nombre (reaplicar esta migración reprograma, no duplica).
select cron.schedule(
  'room-lifecycle-cron',
  '* * * * *',
  $$select private.invoke_room_lifecycle_cron();$$
);

-- ROLLBACK:
-- select cron.unschedule('room-lifecycle-cron');
-- revoke all on function private.invoke_room_lifecycle_cron() from service_role;
-- revoke all on function private.invoke_room_lifecycle_cron() from authenticated;
-- revoke all on function private.invoke_room_lifecycle_cron() from anon;
-- revoke all on function private.invoke_room_lifecycle_cron() from public;
-- drop function if exists private.invoke_room_lifecycle_cron();
-- revoke execute on function public.room_lifecycle_sweep(int) from service_role;
-- revoke all on function public.room_lifecycle_sweep(int) from public, anon, authenticated;
-- drop function if exists public.room_lifecycle_sweep(int);
-- drop trigger if exists room_messages_purge_on_end_trg on public.rooms;
-- revoke all on function public.room_messages_purge_on_end() from public, anon, authenticated;
-- drop function if exists public.room_messages_purge_on_end();
