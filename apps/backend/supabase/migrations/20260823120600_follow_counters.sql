-- =================================================================================================
-- Fase 4 · Tarea 8 (añadido) — `sync_follow_counters`: los contadores de seguidores, sin deriva.
--
-- Plan: docs/superpowers/plans/2026-08-23-contactos-y-mensajeria.md (Tarea 8, paso 3)
--
-- ESTA MIGRACIÓN NO ESTÁ EN LA LISTA DE FICHEROS DE LA TAREA 8, y se añade a propósito. El paso 3
-- pide que `follow-toggle` actualice `profiles.followers_count`/`following_count`, y no hay forma
-- correcta de hacerlo desde la Edge Function:
--
--   · PostgREST no admite expresiones en un `UPDATE`, así que no se puede pedir `col = col + 1`.
--   · Leer-modificar-escribir desde la función es una carrera: dos aceptaciones simultáneas leen el
--     mismo valor y escriben el mismo incremento, y el contador se queda corto para siempre. Nadie
--     lo detecta, porque no hay nada con qué comparar.
--
-- Y un contador que deriva no es un detalle en este repositorio: `badges_count` y
-- `experiences_count` se BORRARON en el Bloque 2 exactamente por eso — eran «estado duplicado y
-- falsificable», y hoy el número se cuenta de la tabla real.
--
-- Por eso esta función NO INCREMENTA: RECALCULA desde `user_follows`, que es la fuente de verdad.
-- Tres propiedades que se ganan con ello, y ninguna con un `+1`:
--   · Es exacta aunque dos peticiones crucen: es UNA sentencia, no una lectura y una escritura.
--   · Es IDEMPOTENTE: llamarla de más no estropea nada.
--   · Es AUTOCORRECTIVA: si un contador ya estaba mal —por una escritura vieja o por un fallo a
--     medias— la siguiente llamada lo arregla sin intervención.
-- =================================================================================================

create or replace function public.sync_follow_counters(p_user_ids uuid[])
returns void
language sql
volatile
security definer
set search_path = ''
as $$
  update public.profiles p
     set followers_count = (
           select count(*) from public.user_follows f
            where f.followee_id = p.user_id and f.status = 'accepted'),
         following_count = (
           select count(*) from public.user_follows f
            where f.follower_id = p.user_id and f.status = 'accepted')
   where p.user_id = any(p_user_ids);
$$;

comment on function public.sync_follow_counters(uuid[]) is
  'Recalcula followers_count/following_count desde `user_follows` para los usuarios dados. '
  'RECALCULA, no incrementa: es exacta ante concurrencia, idempotente y autocorrectiva. Solo cuenta '
  'los follows `accepted` — una solicitud pendiente NO es un seguidor, o repartir solicitudes '
  'inflaria el perfil de cualquiera. La llama `follow-toggle` con service_role.';

-- `security definer` SÍ hace falta aquí, a diferencia de `mint_tag_suffix`: escribe columnas de
-- `profiles` que son territorio exclusivo del backend, y así el privilegio no depende de qué rol
-- acabe llamándola.
--
-- Punto 11 de db-schema: en `public`, PostgREST la expondría como
-- `POST /rest/v1/rpc/sync_follow_counters`. Un usuario podría entonces forzar el recálculo de
-- cualquier perfil — no falsearía nada (recalcula de la fuente de verdad), pero es trabajo de base
-- de datos que dispara quien quiera, gratis. Se revoca.
revoke execute on function public.sync_follow_counters(uuid[]) from public, anon, authenticated;
grant  execute on function public.sync_follow_counters(uuid[]) to service_role;

-- =================================================================================================
-- VERIFICACIÓN POSTERIOR
-- =================================================================================================
--   -- Ningún contador debe divergir de la tabla real. Esta consulta es también la que hay que
--   -- correr si alguna vez se sospecha de los números en producción:
--   select p.user_id, p.followers_count, p.following_count
--     from public.profiles p
--    where p.followers_count <> (select count(*) from public.user_follows f
--                                 where f.followee_id = p.user_id and f.status = 'accepted')
--       or p.following_count <> (select count(*) from public.user_follows f
--                                 where f.follower_id = p.user_id and f.status = 'accepted');
--   -- 0 filas.  Test: apps/backend/supabase/tests/follow-counters.sql

-- =================================================================================================
-- ROLLBACK:
-- =================================================================================================
-- drop function if exists public.sync_follow_counters(uuid[]);
