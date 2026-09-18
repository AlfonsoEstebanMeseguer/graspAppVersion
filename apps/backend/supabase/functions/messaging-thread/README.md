# messaging-thread

Trigger: HTTP (app), `GET /functions/v1/messaging-thread?conversation_id=<uuid>&limit=&before=`.
Una página de mensajes más el estado del input del §9.2. Fase 4, Tarea 11.

Requiere `service_role`: **sí**, por el mismo motivo que `messaging-inbox`: `conversations` no tiene
ningún `grant` para `authenticated`.

## Al saltarse la RLS hay que reimplementar lo que protegía

`service_role` ignora las policies, así que **la pertenencia a la conversación deja de comprobarla
Postgres**. Si este handler no la comprobara, cualquiera con un `conversation_id` leería la
conversación entera de dos desconocidos. Se comprueba contra `conversation_states` —la misma fuente
que usa la policy de `direct_messages`, y de paso trae el `cleared_at`— y se responde **404, no 403**:
un 403 confirmaría que esa conversación existe.

Lo mismo con `deleted_for` (RN-28) y `cleared_at` (RN-27): los aplica `_shared/messaging-view.ts`.
`cleared_at` va **además** en la consulta, pero eso es para no traerse de la red lo que no se va a
enseñar — la garantía es la proyección.

## La cita es por donde se filtra un mensaje que no debería verse

Dos puertas, y las dos están cerradas:

1. **Al leer**: los mensajes citados se piden por id **acotados a esta conversación**. Sin ese
   filtro, un `reply_to_id` manipulado traería una fila de otra conversación para resolverla. Es el
   mismo agujero que `messaging-send` cierra al escribir, cerrado también al leer.
2. **Por visibilidad**: la cita se resuelve contra la **misma** prueba que el mensaje que la
   contiene. Sin esto, borrar un mensaje «para mí» o vaciar el historial dejaría su texto accesible
   a través de cualquier respuesta que lo citara — desaparece de la lista y reaparece dentro de la
   burbuja de otro. Cuando no se puede ver, la cita viaja con `content: null` en vez de omitirse,
   para que el cliente pinte «mensaje no disponible» y no se rompa el hilo.

## El estado del input (§9.2)

Sale de `resolveInputState`, que **no recalcula nada**: llama a `evaluateSendLimits`, el mismo
veredicto que usa `messaging-send`. Es para lo que la Tarea 9 lo hizo devolver un veredicto en vez de
lanzar — si fueran dos cálculos, el input podría decir «puedes escribir» y el envío rechazar, o peor,
divergir justo en el caso del bloqueo.

| Situación | `can_send` | `input_notice` | `messages_left` | `request_actions` |
|---|---|---|---|---|
| Aceptada | `true` | `null` | `null` | `false` |
| Solicitud enviada, con restantes | `true` | `null` | 1-5 | `false` |
| Solicitud enviada, 5 gastados | `false` | el texto | **0** | `false` |
| Solicitud **recibida**, sin aceptar | `true` | `null` | `null` | **`true`** |
| Bloqueado | `false` | el texto | **0** | `false` |

Dos filas que conviene leer con cuidado:

**El `0` de `messages_left` es RN-23, no una simplificación.** Si el número saliera del contador en
bruto, un bloqueado que solo hubiera gastado 2 de sus 5 recibiría `can_send: false` junto a
`messages_left: 3`. Esa combinación **es imposible por un cupo agotado** —sin cupo implica cero
restantes—, así que sería un oráculo de bloqueo perfecto, construido con dos campos que por separado
parecen inocentes. Por eso se deriva del veredicto: no se puede enviar, luego no quedan mensajes.

**La solicitud recibida da `can_send: true` con `request_actions: true`, y no es una contradicción.**
El backend sí aceptaría el envío (RN-08: contestar es aceptar de hecho); la UI enseña las cuatro
acciones de RN-04 en lugar del input. Son dos preguntas distintas —qué pinta el cliente y qué admite
el servidor— y falsear la segunda para que encaje con la primera es justo lo que las hace divergir.

## Paginación

`limit` (1-100, por defecto 30) y `before` (cursor ISO-8601). Se pide una fila de más para saber si
hay siguiente sin contar la tabla entera.

**El cursor sale de la fila cruda más antigua, no del mensaje proyectado más antiguo.** La proyección
descarta filas (RN-27, RN-28), así que si la más antigua de la página resultara invisible para este
espectador, un cursor sacado de la lista proyectada saltaría por encima de ella y la página siguiente
devolvería mensajes ya vistos, o dejaría un hueco.

Los mensajes se piden de más nuevo a más viejo y se devuelven en orden **cronológico ascendente**,
que es como se pintan.

## `activity_status` va con el cliente del usuario

Igual que en `messaging-inbox`, y por lo mismo: la función deriva quién pregunta de `auth.uid()`, que
con la clave de servicio es `NULL`, y devolvería `false` siempre **sin dar error**. Detalle completo
en el README de `messaging-inbox`.

## Verificado de punta a punta en local (2026-08-25)

- emisora con 1 de 5 → `can_send: true`, `messages_left: 4`; con 5 de 5 → el texto del ADR 0022 y `0`;
- receptor de la solicitud → `request_actions: true`;
- **bloqueada con 1 de 5 gastados → estado del input idéntico campo a campo al de 5 de 5**;
- tras ignorar, el hilo de la emisora es **byte a byte idéntico** al de antes (RN-06);
- quien no participa → 404;
- la cita resuelta con su texto y su `from_me` correcto, y `has_more`/`next_before` paginando.

Estado: **implementado, sin desplegar.**
