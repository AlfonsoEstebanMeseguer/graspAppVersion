# follow-toggle

Trigger: HTTP (app). Las cinco acciones sobre el grafo de seguimiento (`§4.3`, `RN-11` a `RN-20`).

Input: `{ action, target_id }` — `action` ∈ `request` · `accept` · `reject` · `unfollow` ·
`remove_follower`.

Output (200): `{ success, action, status }`, donde `status` es `none` | `pending` | `accepted`. En
`accept` añade `conversation_resumed` (`RN-17`).

## La decisión es pura; aquí solo se aplica

`_shared/follow.ts` recibe el estado y devuelve la transición, con 25 tests. Es lo que permite fijar
sin base de datos las cinco reglas que se pierden con facilidad:

| Regla | Qué fija |
|---|---|
| `RN-13` | Aceptar es **unidireccional**: el aceptante no pasa a seguir al solicitante |
| `RN-14` | Aceptar **no** crea conversación |
| `RN-15` | Dejar de seguir **no toca ninguna conversación** |
| `RN-16` | Rechazar **borra la fila**, no la marca — por eso se puede volver a solicitar |
| `RN-20` | 20 solicitudes al día, y la **20 sí pasa** |

`RN-16` merece subrayarse porque es **justo lo contrario de `RN-07`**: un follow rechazado se puede
volver a pedir; un primer mensaje ignorado es terminal para siempre. Si esto guardara un estado
`rejected`, la segunda solicitud sería imposible — y por eso `user_follows.status` no tiene ese valor.

## El rechazo opaco es una sola función, y eso es la garantía

`RN-23` dice que un bloqueo no se revela «ni por texto ni por forma». Rechazar por bloqueo devuelve
**exactamente lo mismo** que rechazar por cuenta inexistente: `404 not_found`, mismo mensaje, mismos
`details`. Que salga de una única función (`rechazoOpaco`) es lo que impide que dos literales
parecidos diverjan al editarlos, y hay un test que los compara campo a campo.

Lo que **no** se promete es indistinguibilidad temporal: el camino del bloqueo hace una consulta más.
Cerrarlo exigiría otro diseño y está fuera del alcance (Global Constraints del plan).

## Los contadores se RECALCULAN, no se incrementan

`PostgREST` no admite expresiones en un `UPDATE`, así que no hay forma de pedir `col = col + 1`; y
leer-modificar-escribir desde aquí es una carrera que deja el contador corto **para siempre**, sin
nada con que compararlo. Este repositorio ya borró `badges_count` y `experiences_count` por ser
«estado duplicado y falsificable».

Por eso `public.sync_follow_counters` (migración `20260823120600`, añadida por esta tarea)
**recalcula desde `user_follows` en una sola sentencia**: exacta ante concurrencia, idempotente y
**autocorrectiva**. Si un contador ya estaba torcido, la siguiente llamada lo endereza. Su fallo no
aborta la petición: la relación ya está bien escrita y el número se arregla solo.

## `RN-17`, el caso que se olvida

Al aceptar un follow, si el ahora aceptado había iniciado una conversación que quedó en `ignored`,
esa conversación **se reanuda** y vuelve a la bandeja de los dos. Dos condiciones lo acotan:

- El `initiator_id` tiene que ser **el solicitante aceptado**. Si fue el otro quien escribió y éste
  la ignoró, aceptar el follow no revive nada suyo.
- **Un bloqueo vigente lo impide.** `RN-17` reanuda un ignorado, **no levanta un bloqueo**.

Las dos mitades verificadas contra el stack local: sin bloqueo, `ignored hidden=false/true` pasa a
`accepted hidden=false/false`; con bloqueo, la llamada devuelve el 404 opaco y la conversación sigue
`ignored` con el follow en `pending`.

## Matiz honesto sobre el tope de RN-20

Se cuentan las solicitudes que **siguen pendientes** dentro de la ventana móvil de 24 h, no las
enviadas: una aceptada deja de contar y libera cupo. Es lo que pide el plan (contarlo sobre el índice
parcial de la Tarea 2) y es lo razonable — el tope existe contra el reparto masivo de solicitudes a
desconocidos, y una solicitud aceptada no es eso.

## Lo que esta función NO hace

- **No corta follows al bloquear.** Es deliberado y está en `docs/pending-messaging.md`: si A bloquea
  a B y B deja de seguir a A de golpe, B lo nota — y eso choca con `RN-23`. Un follow que sobrevive
  es inocuo, porque el bloqueado no puede actuar.
- **No notifica nada.** No hay push ni badge al recibir una solicitud; eso llega con las
  notificaciones.
