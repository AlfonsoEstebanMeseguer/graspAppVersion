# messaging-actions

Trigger: HTTP (app), `POST /functions/v1/messaging-actions`. Las acciones sobre una **conversación**.
Fase 4, Tarea 12.

Requiere `service_role`: **sí**. `conversations` no tiene ningún `grant` para `authenticated`, y de
`conversation_states` solo se le conceden `unread_count` y `notifications_enabled` — `hidden` y
`cleared_at` no, porque archivar y vaciar el historial son acciones con consecuencias y pasan por
aquí.

| `action` | Efecto | Quién puede |
|---|---|---|
| `accept` | `status = 'accepted'` (RN-05) | **solo quien recibió** la solicitud |
| `ignore` | `status = 'ignored'` + `hidden` **solo de quien ignora** (RN-06) | **solo quien recibió** |
| `delete_history` | `cleared_at = now()` + `hidden`, solo de quien lo pide (RN-27) | cualquier participante |
| `mark_read` | `unread_count = 0` propio (RN-31) | cualquier participante |
| `set_notifications` | persiste el valor y nada más (§9.3 punto 1) | cualquier participante |

## El invariante que sostiene RN-06 y RN-31 a la vez

**Ninguna acción escribe en la fila del otro participante.** No es una convención: el tipo
`StateWrite` lleva el `userId` **dentro** de cada escritura en vez de darlo por supuesto, y hay un
test que recorre el enum entero de acciones y comprueba que ninguna produce una escritura ajena.

Un tipo que solo pudiera expresar «el actor» haría el invariante cierto por construcción, pero
también invisible — y el día que alguien necesitara escribir en la otra fila, lo añadiría sin que
ningún test dijera nada.

Verificado además contra la base: tras el `ignore` de Ben, la fila de Ana seguía con
`hidden=false unread=0 notif=true cleared=-`, exactamente como antes.

## `ignore` y el trigger de entrega son las dos mitades de la misma regla

Aquí se pone `hidden = true` **solo** en la fila de quien ignora. El trigger
`direct_messages_delivery` (migración `20260825120000`) hace la otra mitad: **no toca nada del
receptor** cuando la conversación está `ignored`. Si cualquiera de las dos mitades faltara, los
mensajes 2..5 del emisor desharían el rechazo. Razones completas en el
[ADR 0023](../../../../../docs/decisions/0023-el-ignorar-sobrevive-a-los-mensajes-pendientes.md).

Comprobado de punta a punta: con la conversación ya ignorada **de verdad** por este endpoint, el
mensaje 2 de Ana devolvió `messages_left: 3` —lo mismo que una pendiente— y Ben siguió con
`hidden=true`, `unread=0` y las dos bandejas vacías.

## Aceptar la solicitud propia es un 403, no un no-op

Un no-op silencioso taparía el intento de colarse en los Contactos de otro sin que esa persona haga
nada. Se rechaza con 403 y se ve.

`accept` sobre una conversación **ya ignorada** es un no-op, no una resurrección: `ignored` es
terminal (RN-07). Lo único que reanuda una ignorada es RN-17, y vive en `follow-toggle` (al aceptar
el follow de quien escribió).

`ignore` sobre una conversación ya `accepted` es un **422**: las cuatro acciones de RN-04 solo se
ofrecen sobre una solicitud sin aceptar (§9.2 fila 4). Sobre una aceptada lo que hay es bloquear o
vaciar.

## Errores

`400` action fuera del enum, `conversation_id` no uuid, o `set_notifications` sin booleano (no se
asume un valor por defecto) · `401` · `403` la acción no le corresponde a quien la pide · `404`
no existe **o no participas**, el mismo cuerpo para los dos: un 403 confirmaría que existe ·
`405` · `422` la acción no cabe en ese estado · `500`.

La respuesta **no lleva el `status`** de la conversación. El actor sabe lo que acaba de hacer, y no
emitirlo mantiene la regla de que `status` no sale de la base por ningún endpoint (RN-06).

## Verificado de punta a punta en local (2026-08-25)

Emisora intentando aceptar lo suyo → 403 · no participante → 404 · `ignore` aplicado con la fila del
emisor intacta · `ignore` repetido → `applied: false` · `mark_read` y `set_notifications`
persistiendo · `set_notifications` sin booleano → 400 · `delete_history` marcando `cleared_at` y
`hidden` **sin borrar ni una fila de `direct_messages`** (el otro conserva su historial íntegro).

Estado: **implementado, sin desplegar.**
