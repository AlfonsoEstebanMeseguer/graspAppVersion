# messaging-send

Trigger: HTTP (app). Envía un mensaje directo: abre la conversación si no existía, la enruta (§4.2)
y la entrega. Fase 4, Tarea 10 del plan `2026-08-23-contactos-y-mensajeria.md`.

Requiere `service_role`: **sí**. `conversations` no tiene **ni un `grant`** para `authenticated` —
es lo que hace estructural, y no confiada al cuidado de quien escriba el endpoint, la invisibilidad
de `status = 'ignored'` y de `initiator_id` (RN-06).

## Cómo se reparte el trabajo

| Dónde | Qué decide |
|---|---|
| `_shared/messaging-limits.ts` | **¿Se puede enviar?** Devuelve un veredicto; no lanza (RN-01, RN-07, RN-18, RN-19, RN-21, RN-23) |
| `_shared/messaging-routing.ts` | **¿A qué estado nace o se reutiliza el hilo?** (§4.2, RN-08, RN-09, RN-10) |
| `index.ts` | Carga el estado de Postgres, aplica el veredicto y escribe |
| Trigger `direct_messages_delivery` | `last_message_at`, `unread_count` del receptor y `hidden` |

Las dos primeras son puras y tienen 35 tests que corren sin red ni credenciales.

## Las tres cosas que este handler NO hace, y por qué

### 1. No incrementa `unread_count` — lo hace un trigger

Está en la migración `20260825120000_message_delivery.sql`, y el motivo **no** es el mismo que el de
`sync_follow_counters` (Tarea 8), aunque el muro inicial se parezca:

- PostgREST no admite expresiones en un `UPDATE`, así que `unread_count = unread_count + 1` no se
  puede pedir desde el cliente Supabase, y leer-modificar-escribir desde Deno es una carrera.
- Pero, a diferencia de los seguidores, **lo no leído no se deriva de ninguna tabla**. `read_at` está
  prohibida por RN-31 «ahora ni nunca» (ADR 0021). `sync_follow_counters` puede RECALCULAR desde
  `user_follows`, así que es autocorrectivo y `follow-toggle` se permite un `console.warn` si falla.
  Aquí no hay nada desde donde recalcular ni con qué comparar: **un incremento perdido es permanente
  e indetectable.**

Un RPC llamado después del `insert` puede perderse —el mensaje commitea, la llamada muere— y deja
exactamente ese daño. Un trigger `after insert` corre en la misma transacción: o hay mensaje y
contador, o no hay ninguno de los dos.

### 2. En una conversación `ignored` no toca nada del receptor — enmienda al plan

El paso 3 de la Tarea 10 pedía poner `hidden = false` «en los dos». **No se puede**, y es una
contradicción entre dos pasos del mismo plan: el paso 1 de la Tarea 12 hace del `hidden` del receptor
*el* mecanismo del ignorar (`ignore` → `status='ignored'` + `hidden` solo del receptor). Aplicar los
dos significa que los mensajes 2..5 del emisor **deshacen el rechazo** y devuelven a la bandeja del
receptor una conversación que pidió no ver.

Manda RN-06/RN-07 — `ignored` es **terminal**. RN-27 promete que una conversación reaparece cuando el
otro escribe, pero eso es sobre un historial que el usuario **borró**, no sobre una conversación que
**rechazó**. El `unread_count` va en el mismo paquete: un badge que sube por una conversación que no
aparece en ninguna de las dos pestañas es un número que no se puede bajar nunca, porque no hay
pantalla donde marcarlo leído.

Razones completas: `docs/decisions/0023-el-ignorar-sobrevive-a-los-mensajes-pendientes.md`.

Lo que **sí** se sigue haciendo en una ignorada, y es obligatorio: subir `last_message_at` y dejar el
lado del emisor idéntico al de una pendiente. Si su hilo dejara de ascender en Contactos al escribir,
sería observable — y RN-06 dice que el emisor no se entera de nada.

### 3. No hace falta ninguna excepción para el bloqueo: sale antes de escribir

La excepción de RN-23 del paso 3 («si quien escribe está bloqueado, se rechaza sin tocar `hidden`»)
se cumple **por el orden**, no por un `if`. `evaluateSendLimits` comprueba el bloqueo el primero, el
handler devuelve el 422 antes de escribir nada y el trigger de entrega no llega a dispararse.
Verificado en vivo: tras el intento, el `hidden` del bloqueador seguía en `true` y no había mensaje
nuevo.

## El orden de las comprobaciones, que no es indiferente

1. **Idempotencia primero.** Si se comprobaran los límites antes, el reintento del **quinto** mensaje
   se evaluaría como si fuera el sexto —porque el quinto ya está escrito— y devolvería un 422 por un
   mensaje que sí se entregó. Verificado: el reintento devuelve `messages_left: 4`, no 3.
2. Bloqueo (dentro del veredicto, y el primero de todos: si se comprobara después, un bloqueado con
   cupo y otro sin cupo recibirían motivos distintos, que es una fuga).
3. Límites → 4. Enrutado → 5. `reply_to_id` **antes** del insert → 6. El mensaje.

`reply_to_id` tiene que pertenecer a **esa** conversación: sin la comprobación se puede citar un
mensaje de otra y filtrar su texto al pintar la cita.

## Lo que nunca sale en la respuesta

`status`, `initiator_id`, el `unread_count` del otro y **`internalReason`**. El 422 se construye en
`blockedResponse()`, que recibe el veredicto entero y **solo lee sus campos públicos**: un bloqueo y
un cupo agotado producen el mismo cuerpo byte a byte porque salen del mismo cálculo, no porque
alguien se acuerde de copiarlos iguales. Comprobado en vivo con una comparación de cadenas.

`messages_left` se calcula solo con los mensajes enviados, sin mirar el estado, así que una
conversación ignorada devuelve exactamente el mismo número que una pendiente.

## Verificado de punta a punta en local (2026-08-25)

Alta real vía `POST /auth/v1/signup` y `curl` contra la función servida:

- primer mensaje → 200, `messages_left: 4`;
- misma `idempotency_key` → **el mismo mensaje**, `idempotent_replay: true`, `messages_left: 4`;
- mensajes 2..5 → 3, 2, 1, 0; el **sexto** → 422 `quota_exhausted`, `limit: 5` (RN-01);
- respuesta del otro → RN-08: **un solo hilo**, pasa a `accepted` y `messages_left: null`;
- `reply_to_id` de otra conversación → 422 `invalid_reply_target`;
- bloqueado → 422 **idéntico byte a byte** al de cupo agotado, y el lado del bloqueador intacto;
- conversación ignorada → el mensaje entra, el emisor ve lo mismo que en una pendiente, y el receptor
  conserva `hidden = true` y `unread_count = 0`;
- sexta conversación en 24 h → 422 `too_many_first_messages` con el `retry_at` de la más antigua
  saliendo de la ventana, no «24 h desde ahora» (RN-21).

Estado: **implementado, sin desplegar.** Nada de la Fase 4 está en producción.
