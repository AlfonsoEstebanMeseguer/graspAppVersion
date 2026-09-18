-- =================================================================================================
-- Fase 4 · Tarea 4 — El punto de actividad, sin filtrar una marca de tiempo.
--
-- Plan: docs/superpowers/plans/2026-08-23-contactos-y-mensajeria.md (Tarea 4)
-- Spec: docs/spec-contactos-mensajes-conectar.md (RN-30 el punto verde/gris, RN-32 ocultarlo)
--
-- Los dos RPC de este fichero existen para que `profiles_private.last_seen_at` NUNCA salga de la
-- base de datos. La columna se creó en la Tarea 1 dentro de `profiles_private` —y no en `profiles`—
-- justamente porque una marca de última conexión exacta y pública es una herramienta de acecho; si
-- ahora un RPC la devolviera, esa decisión no habría servido de nada. Por eso:
--
--   · `touch_last_seen()` ESCRIBE la marca y no devuelve nada.
--   · `activity_status()` LEE la marca y devuelve un BOOLEANO. Nunca el timestamp, ni derivados
--     suyos (ni "hace N minutos", ni el propio `last_seen_at` redondeado).
--
-- Las dos son `security definer` porque `authenticated` no tiene `update` ni sobre `last_seen_at`
-- (Tarea 1, y no debe tenerlo), y porque leer la fila ajena de `profiles_private` está cerrado por
-- la policy `profiles_private_read_own` — que es exactamente lo que se quiere conservar.
-- =================================================================================================

-- =================================================================================================
-- 1) `touch_last_seen()` — el latido
-- =================================================================================================

-- Escribe `now()` en la fila propia y NADA MÁS: ni acepta parámetro de usuario, ni de instante. Que
-- no reciba argumentos es la garantía de que nadie puede latir por otro ni fingir una hora: el
-- único usuario que puede tocar es `auth.uid()`, y el único valor que puede escribir es el reloj
-- del servidor.
create or replace function public.touch_last_seen()
returns void
language sql
volatile
security definer
set search_path = ''
as $$
  update public.profiles_private
     set last_seen_at = now()
   where user_id = (select auth.uid());
$$;

comment on function public.touch_last_seen() is
  'Latido de actividad (RN-30). Escribe now() en profiles_private.last_seen_at del propio usuario. '
  'Sin parametros a proposito: nadie puede latir por otro ni elegir el instante. Si no hay sesion, '
  'auth.uid() es NULL y no actualiza ninguna fila (falla cerrado, sin error).';

-- =================================================================================================
-- 2) `activity_status(uuid[])` — el punto, y solo el punto
-- =================================================================================================

-- Devuelve `table(user_id uuid, is_active boolean)`. NUNCA una marca de tiempo.
--
-- RN-32 ES RECÍPROCO, y esa reciprocidad vive AQUÍ DENTRO, no en el cliente ni en la Edge Function:
-- quien oculta su actividad tampoco ve la de los demás. Si estuviera en la capa de arriba, bastaría
-- una llamada directa al RPC —que `authenticated` puede hacer— para saltársela.
--
-- Propiedad que conviene no perder al tocar esto: un uuid inexistente y un uuid de alguien inactivo
-- devuelven EXACTAMENTE lo mismo (`false`), así que este RPC no sirve para averiguar si una cuenta
-- existe. Mantenerlo así es lo que impide convertirlo en un enumerador.
create or replace function public.activity_status(p_user_ids uuid[])
returns table (user_id uuid, is_active boolean)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_caller uuid := (select auth.uid());
  v_caller_hides boolean;
begin
  -- Tope defensivo: este RPC lo puede llamar cualquier `authenticated` con el array que quiera, y
  -- sin cota un solo POST podría pedir cien mil comprobaciones. Las pantallas que lo usan paginan
  -- (la bandeja y el feed de Conectar), así que 500 sobra de largo. Se rechaza en vez de truncar en
  -- silencio: devolver menos filas de las pedidas haría que el llamante pintara puntos grises sin
  -- saber por qué.
  if p_user_ids is null or array_length(p_user_ids, 1) is null then
    return;
  end if;

  if array_length(p_user_ids, 1) > 500 then
    raise exception 'activity_status admite como maximo 500 ids por llamada (recibidos %)',
      array_length(p_user_ids, 1)
      using errcode = 'program_limit_exceeded';
  end if;

  -- Sin sesión no hay punto de actividad para nadie.
  if v_caller is null then
    return query
      select u.id, false from unnest(p_user_ids) as u(id);
    return;
  end if;

  select coalesce(pp.hide_activity_status, false)
    into v_caller_hides
    from public.profiles_private pp
   where pp.user_id = v_caller;

  -- RN-32 recíproco: quien oculta no ve. Se resuelve antes de mirar a nadie.
  if coalesce(v_caller_hides, false) then
    return query
      select u.id, false from unnest(p_user_ids) as u(id);
    return;
  end if;

  return query
    select u.id,
           coalesce(
             (select pp.last_seen_at > now() - interval '2 minutes'
                 and not pp.hide_activity_status
                from public.profiles_private pp
               where pp.user_id = u.id),
             false)
      from unnest(p_user_ids) as u(id);
end;
$$;

comment on function public.activity_status(uuid[]) is
  'Punto de actividad (RN-30): devuelve un BOOLEANO por usuario, nunca la marca de tiempo — esa es '
  'la razon de ser de esta funcion y de que `last_seen_at` viva en `profiles_private`. Activo = '
  'latido en los ultimos 2 minutos y sin ocultar. RN-32 es RECIPROCO y se aplica aqui dentro: si '
  'quien llama oculta su actividad, recibe `false` para todos. Un uuid inexistente devuelve lo '
  'mismo que uno inactivo, asi que no sirve para enumerar cuentas.';

-- =================================================================================================
-- 3) GRANTS DE EJECUCIÓN
--    Punto 11 de db-schema: cualquier funcion de `public` la expone PostgREST como
--    `POST /rest/v1/rpc/<nombre>` ejecutable por anon/authenticated salvo que se revoque. Aqui la
--    exposicion a `authenticated` SI se quiere (las llama la app), pero a `anon` no, y el `revoke`
--    de `public` es el que quita la concesion implicita a todo el mundo.
-- =================================================================================================

revoke execute on function public.touch_last_seen() from public, anon;
grant  execute on function public.touch_last_seen() to authenticated;

revoke execute on function public.activity_status(uuid[]) from public, anon;
grant  execute on function public.activity_status(uuid[]) to authenticated;

-- El `revoke ... from public` de arriba tambien le alcanza a `service_role`: no es superusuario, asi
-- que sin este grant explicito responderia `permission denied for function`.
--
-- CORRECCION 2026-08-25 (Tarea 11). Este comentario decia que el grant existe porque `messaging-inbox`
-- y `connect-feed` resuelven el punto server-side. **Llamarla con `service_role` NO FUNCIONA**, y lo
-- peor es que no falla: esta funcion deriva quien pregunta de `auth.uid()`, que con la clave de
-- servicio es NULL, asi que devuelve `false` para TODO el mundo. Comprobado contra la base, no
-- deducido: con un token sin `sub`, un usuario activo sale `false`; con su `sub`, sale `true`.
-- Ademas RN-32 es reciproco —quien oculta no ve— y eso solo se puede evaluar mirando al llamante.
--
-- Las Edge Functions la llaman con el CLIENTE DEL USUARIO (`requireAuthUser` ya devuelve uno). El
-- grant se queda por si algun dia hace falta un camino interno, pero usarlo para la bandeja o para
-- Conectar rompe RN-30 y RN-32 sin un solo error en los logs.
grant execute on function public.activity_status(uuid[]) to service_role;

-- =================================================================================================
-- VERIFICACIÓN POSTERIOR (a mano tras aplicar; la migración no la hace)
-- =================================================================================================
--   select p.proname, p.prosecdef,
--          coalesce(array_to_string(p.proacl, ' | '), '(por defecto: PUBLIC)') as acl
--     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--    where n.nspname = 'public' and p.proname in ('touch_last_seen', 'activity_status');
--   -- las dos con prosecdef = t, y en el ACL NI RASTRO de `anon` ni de `=X/` para PUBLIC.
--
--   -- Y lo que de verdad importa: que ningun camino devuelva un timestamp.
--   select pg_get_function_result(p.oid) from pg_proc p ...   -- boolean, nunca timestamptz.
--   Test completo: apps/backend/supabase/tests/activity-status.sql

-- =================================================================================================
-- ROLLBACK:
-- =================================================================================================
-- drop function if exists public.activity_status(uuid[]);
-- drop function if exists public.touch_last_seen();
