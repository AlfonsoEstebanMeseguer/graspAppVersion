# room-lifecycle-cron

Trigger: CRON (cada 1 min), vía `private.invoke_room_lifecycle_cron()`
(`20260901130000_rooms_cron.sql`). Cierra salas `status = 'live'` por: 2h alcanzadas (`expired`),
vacía 10min (`empty`), sin actividad 10min (`idle`). Anfitrión ausente lo cierra `room_leave`
(`host_left`), no este cron.

Toda la regla vive en el RPC `room_lifecycle_sweep(p_limit)`: esta función solo autentica
(`requireInternalCaller`, token dedicado — nunca `verify_jwt` ni la `service_role key`) e invoca el
RPC con `service_role`. El freno **acota, no aborta**: procesa como mucho `p_limit` salas por pasada
y devuelve `capped: true` si quedaba trabajo.

Los mensajes de una sala terminada se borran con un **trigger** sobre `rooms`
(`room_messages_purge_on_end`), no aquí — cubre también `room_leave` y `room_end`, los otros dos
caminos por los que una sala puede terminar.

Contrato completo: `docs/api-contracts.md` § `room-lifecycle-cron`.
Ver Sección 11 y 12.E del documento maestro. Fase 5 — Sección 8, Tarea 5.
