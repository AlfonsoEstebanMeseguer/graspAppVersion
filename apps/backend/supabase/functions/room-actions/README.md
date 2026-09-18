# room-actions

Trigger: HTTP (app), `service_role`. `POST /room-actions` con cuerpo
`{ action, roomId?, title?, categoryId?, targetUserId?, note? }` y
`action` en `create | join | leave | raise_hand | grant_speak | revoke_speak | end`.

Toda escritura de estado de una sala pasa por aquí — el cliente Flutter nunca
toca `rooms` ni `room_participants` directamente (RLS de esas tablas no tiene
policies de escritura a propósito). Las reglas de negocio (aforo de 20, tope
de 2 hablantes, quién es el host) **no viven en esta función**: viven en las
funciones de Postgres `room_create`, `room_join`, `room_raise_hand`,
`room_grant_speak`, `room_revoke_speak`, `room_end` y `room_leave`
(`20260901120000_rooms.sql`), porque tienen que contarse con `for update`
dentro de la misma transacción que escribe — contarlas aquí y escribir
después es una carrera que dos peticiones simultáneas ganan las dos. Esta
función solo valida la forma del input y traduce los `errcode = 'P0001'` de
Postgres a códigos HTTP.

Las siete funciones de escritura son `security definer` y llevan
`revoke all ... from public, anon, authenticated`, así que necesitan un
`grant execute ... to service_role` explícito — `BYPASSRLS` no es
`BYPASSGRANT` (punto 12 de `rls-security`). Esto se olvidó al escribirlas por
primera vez (vuelta de arreglos 1, 2026-08-31) aunque el mismo patrón ya
estaba documentado y resuelto para `room_max_occupants()`/`room_max_speakers()`
en el mismo fichero: sin el grant, `room-actions` devuelve
`permission denied for function` en cualquier entorno nuevo, y ningún test
que corra como `postgres` (el dueño) puede detectarlo.

`end` **no es un alias de `leave`**: `leave` es que un participante se va,
`end` es que el host cierra la sala para todos con `ended_reason =
'host_ended'`. `room_end` comprueba que quien llama es el host y falla con
`not_the_host` si no lo es.

Máximo 2 hablantes simultáneos se valida aquí, en backend (nunca solo en UI) — ver Sección 14.
Fase 5 y 6 — Sección 8 del documento maestro.

Tests: `apps/backend/supabase/tests/rooms-actions.sql` (aforo, tope de
hablantes, `revoke_speak` libera el escenario, `room_end` solo el host,
ejecución con `service_role` real, reunirse dos veces da `already_in_room`
en vez de un 500 crudo, y un caso de concurrencia real con `dblink` —solo
desarrollo local— que fuerza la carrera del aforo desde dentro del propio
script).
