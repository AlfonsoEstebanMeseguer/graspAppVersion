# messaging-message-actions

Trigger: HTTP (app), `POST /functions/v1/messaging-message-actions`. Las acciones sobre **un
mensaje** (RN-28). Fase 4, Tarea 12.

Requiere `service_role`: **sí**. `direct_messages` solo concede `select` a `authenticated`, y con
razón — si el cliente pudiera hacer `update`, RLS filtraría la **fila** pero no las **columnas**, así
que cualquiera podría marcar `deleted_for_all_at` en el mensaje del otro.

| `action` | Efecto | Quién puede |
|---|---|---|
| `delete_for_me` | añade el actor a `deleted_for` | **cualquier participante**, autor o no: es su copia |
| `delete_for_all` | `content = null` **y** `deleted_for_all_at` | **solo el autor** |
| `edit` | `content` nuevo + `edited_at` | **solo el autor** |

## Lo que autoriza es participar, no ser autor

La pertenencia se comprueba sobre la **conversación** del mensaje, no sobre el mensaje: borrar «para
mí» lo hace precisamente quien no escribió. La autoría la comprueba la función pura, donde toca.

**404 y no 403**, y aquí importa el doble: un 403 confirmaría que ese id de mensaje existe, y
permitiría enumerar mensajes ajenos probando uuids.

## Los dos campos de la lápida van en el mismo patch

La constraint `direct_messages_content_or_tombstone` exige `content is null` en cuanto hay lápida.
Un patch a medias no es «incompleto»: es un **500**. Y poner `content` a null es lo que impide que un
cliente que ignore la bandera siga pintando el texto.

Por el mismo motivo **no se puede editar una lápida** → `422`. Sin ese guardia el `UPDATE` dejaría
`content` no nulo con `deleted_for_all_at` puesto: la constraint lo rechaza (un 500 en vez de un 422)
y, si algún día se relajara, un mensaje borrado para todos resucitaría con texto nuevo.

## Editar con el mismo texto es un no-op

El tag «editado» lo ven **los dos** (RN-28). Ponerlo por un guardado idéntico le diría al otro que
estuve editando cuando no cambié una coma.

## El cerrojo optimista de `delete_for_me`, y por qué existe

`deleted_for` es un array que se calcula **leyendo y reescribiendo entero** — PostgREST no sabe hacer
`array_append`. Si los dos participantes borran el mismo mensaje a la vez, el segundo `UPDATE`
pisaría al primero y una de las dos personas volvería a ver el mensaje.

Por eso el `UPDATE` exige que el array **siga siendo el que se leyó**. Quien pierde la carrera no
escribe nada y recibe un **409** en vez de que su borrado se descarte en silencio; el cliente
reintenta y la segunda pasada ya ve el array actualizado.

> **Comprobado que el cerrojo se aplica de verdad, no solo que no estorba.** Que la llamada normal
> funcione es compatible con las dos hipótesis: que PostgREST reenvíe el filtro, y que lo ignore. Se
> discriminó mutando el handler para que mandase un array que no casa: respondió **409** y la fila
> quedó intacta. Sin esa prueba, el cerrojo podría haber sido decorativo.

Para `delete_for_all` y `edit` basta con exigir que el mensaje no se haya convertido en lápida entre
la lectura y la escritura — es lo que impide editar algo que el propio autor acaba de borrar para
todos desde otro dispositivo.

## RN-26 vive en un solo sitio

La longitud (1-1000) sale de `normalizeMessageContent` en `_shared/validation.ts`, **la misma** que
usa `messaging-send`. Editar es el segundo camino por el que nace un `content`, y la regla tiene que
valer igual en los dos (`db-schema` punto 4d: enumera **todos** los caminos de escritura). Tenerla en
dos literales `1000` es exactamente cómo divergen. Se mide en **puntos de código**, como
`char_length` en Postgres.

## Errores

`400` action fuera del enum, `message_id` no uuid, o `content` fuera de 1-1000 · `401` · `403` no
eres el autor · `404` el mensaje no existe **o no participas en su conversación** · `405` ·
`409` el mensaje cambió mientras se aplicaba la acción · `422` no se puede editar una lápida · `500`.

## Verificado de punta a punta en local (2026-08-25)

`delete_for_me` de quien **no** es el autor → aplicado · repetido → `applied: false` ·
`delete_for_all` y `edit` de quien no es el autor → 403 · no participante → 404 · edición marcando
`edited_at` · **el mismo texto → `applied: false` sin volver a marcar** · `delete_for_all` dejando
`content=NULL` con la lápida y conservando `deleted_for` · editar la lápida → 422 · 1001 caracteres
→ 400.

Estado: **implementado, sin desplegar.**
