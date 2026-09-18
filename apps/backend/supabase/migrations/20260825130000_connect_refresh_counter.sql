-- =================================================================================================
-- Fase 4 · Tarea 16 — El contador de `pull-to-refresh` de Conectar, en UNA sentencia.
--
-- Plan: docs/superpowers/plans/2026-08-23-contactos-y-mensajeria.md (Tarea 16, paso 2)
-- Spec: docs/spec-contactos-mensajes-conectar.md (RN-46, RN-21)
--
-- AÑADIDA DURANTE LA EJECUCIÓN, por el mismo muro que la Tarea 10 se encontró con `unread_count`:
-- PostgREST no admite expresiones en un UPDATE, así que `refresh_count = refresh_count + 1` no se
-- puede escribir desde la Edge Function, y leer-modificar-escribir es una carrera.
--
-- Aquí el contador NO SE PUEDE RECALCULAR —no se deriva de ninguna tabla, igual que lo no leído—,
-- así que el incremento tiene que ser atómico (punto 9b de db-schema). La diferencia con la Tarea
-- 10 es que allí la causa era un `insert` y bastó un trigger; aquí la causa es una llamada HTTP sin
-- fila propia, así que el incremento va en un RPC de una sola sentencia: el `on conflict do update`
-- lee y escribe dentro de la misma, sin ventana en la que dos peticiones se pisen.
--
-- EL ORDEN IMPORTA Y ES DELIBERADO: `connect-feed` incrementa PRIMERO y decide después con el valor
-- devuelto. Al revés —comprobar y luego incrementar— vuelve a abrir la carrera que este fichero
-- existe para cerrar. Un intento rechazado deja el contador subido, y es correcto: el tope se
-- reinicia solo cada día (la fecha va en la PK), así que no hay estado absorbente que rearmar.
-- =================================================================================================

-- Devuelve el número de refrescos usados HOY, ya contando el actual.
--
-- `security definer` porque `connect_feed_runs` no tiene grants para `authenticated` (migración
-- `20260823120400`, deny by default) y esta función se llama con `service_role`, que tiene
-- BYPASSRLS pero NO BYPASSGRANT (punto 12 de rls-security).
--
-- `search_path = ''` y todo cualificado: sin esto, un esquema en el `search_path` del llamante
-- podría suplantar `connect_feed_runs`.
create or replace function public.bump_connect_refresh(p_user_id uuid)
returns int
language sql
volatile
security definer
set search_path = ''
as $$
  insert into public.connect_feed_runs (user_id, ran_on, refresh_count)
  values (p_user_id, current_date, 1)
  on conflict (user_id, ran_on)
  do update set refresh_count = public.connect_feed_runs.refresh_count + 1
  returning refresh_count;
$$;

comment on function public.bump_connect_refresh(uuid) is
  'RN-46: suma 1 al contador de pull-to-refresh de hoy y devuelve el total ya contando el actual. '
  'Una sola sentencia para que el incremento sea atomico: PostgREST no puede escribir '
  'refresh_count = refresh_count + 1 y leer-modificar-escribir es una carrera. Quien llama '
  'incrementa PRIMERO y decide despues con el valor devuelto.';

-- Punto 11 de db-schema: cualquier función de `public` es un RPC de PostgREST salvo que se revoque.
-- Sin este `revoke`, cualquier usuario registrado podría llamarla y gastarse (o regalarse) refrescos
-- ajenos, porque recibe el `user_id` por parámetro.
revoke execute on function public.bump_connect_refresh(uuid) from public, anon, authenticated;
grant  execute on function public.bump_connect_refresh(uuid) to service_role;

-- =================================================================================================
-- VERIFICACIÓN — que el contador SUBE y que no lo puede llamar quien no debe
-- =================================================================================================
--   -- 1) Sube de verdad, y la segunda llamada devuelve 2 (no 1 dos veces):
--   select public.bump_connect_refresh('<uuid>');  -- 1
--   select public.bump_connect_refresh('<uuid>');  -- 2
--
--   -- 2) `authenticated` NO puede ejecutarla (debe dar "permission denied for function"):
--   set local role authenticated;
--   select public.bump_connect_refresh('<uuid>');
--
--   -- 3) El estado real de los privilegios, que no se deduce leyendo esta migración:
--   select grantee, privilege_type from information_schema.routine_privileges
--    where routine_name = 'bump_connect_refresh';

-- =================================================================================================
-- ROLLBACK:
-- =================================================================================================
-- drop function if exists public.bump_connect_refresh(uuid);
