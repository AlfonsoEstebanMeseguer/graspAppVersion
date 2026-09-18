# rooms-feed

Trigger: HTTP (app), cliente del usuario. `GET /rooms-feed?categoryId=<uuid>`
(`categoryId` opcional). Responde `{ rooms: [...] }` — ver
`docs/api-contracts.md` para la forma completa de cada sala.

La lista de salas activas (ADR 0032,
`docs/decisions/0032-el-feed-de-salas-no-se-personaliza.md`): no se ordena
por afinidad ni por categorías de interés, solo por `last_activity_at`
descendente, con un filtro de categoría opcional. Toda la lógica vive en el
RPC de Postgres `rooms_feed` (`20260901120000_rooms.sql`); esta función solo
valida `categoryId` y traduce las filas al shape que consume el cliente,
incluyendo la cadena de avatares con `_shared/rooms.ts#pickCardAvatars`.

**Se llama con el cliente del usuario, nunca con `service_role`.**
`rooms_feed` filtra por `auth.uid()`; una `service_role key` es un JWT sin
`sub`, así que `auth.uid()` saldría `NULL` y el filtro de bloqueos no
filtraría nada — **sin dar ningún error** (punto 11 de `edge-functions`).
Por eso `rooms_feed` ni siquiera concede `execute` a `service_role`: si
algún día alguien la llama con la clave de servicio por error, falla cerrado
con `permission denied for function` en vez de devolver un feed sin
filtrar en silencio.

El RPC es `security definer`, no `invoker`, y es deliberado: la RLS de
`public.blocks` (`blocks_read_own`, RN-23) solo deja ver a `authenticated`
las filas donde `blocker_id = auth.uid()` — es la regla que impide que el
bloqueado sepa que le han bloqueado. Con `security invoker`, la mitad "el
host me bloqueó a mí" (`blocker_id = host`, `blocked_id = yo`) sería
invisible para mi propia consulta, y su sala seguiría saliendo en mi feed.
Comprobado a mano: con `security invoker` la función ni siquiera llega a
ese punto, porque además revienta con `permission denied for column
left_at` (ver el párrafo de abajo) — las dos roturas están documentadas en
el comentario de la migración.

`participants` viaja empaquetado dentro del propio RPC (un `jsonb` con
`userId`/`role`/`joinedAt` por cada ocupante vivo), no como una segunda
consulta de esta función contra `room_participants` filtrando
`left_at is null`: esa columna **no está** en el grant de `authenticated`
sobre esa tabla (`id, room_id, user_id, role, joined_at, hand_raised_at,
hand_raised_note`), y PostgREST exige privilegio de `SELECT` sobre una
columna para poder *filtrar* por ella, no solo para devolverla. Como
`rooms_feed` ya es `security definer`, resolverlo ahí evita pedir un grant
nuevo sobre una columna que, a propósito, nadie más lee.

Fase 5, Tarea 4 — Sección 8 del documento maestro.

Tests: `apps/backend/supabase/tests/rooms-feed.sql` (un caso de control sin
ningún bloqueo de por medio que afirma que el feed NO está vacío y que
contiene la sala; las dos direcciones del bloqueo — yo bloqueo al host, el
host me bloquea a mí — cada una probando que la sala no aparece; el orden
por actividad reciente, sin reordenar en la consulta de fuera para que la
mutación se pueda detectar de verdad; el filtro de categoría; el `jsonb` de
`participants`; y el `EXECUTE` de `authenticated` comprobado contra
`information_schema.routine_privileges`, no contra la migración).
