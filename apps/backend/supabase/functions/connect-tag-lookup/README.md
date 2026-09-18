# connect-tag-lookup

Trigger: HTTP (app), `POST /functions/v1/connect-tag-lookup`. Búsqueda por tag exacto (§6.2).
Fase 4, Tarea 16.

Requiere `service_role`: **sí**. Resuelve el tag contra **cualquier** perfil y lee `blocks`, que solo
lo lee su `blocker_id` (RN-23): con el cliente del usuario, la mitad «me bloquearon a mí» sería
invisible y el bloqueo no taparía nada.

## Sin búsqueda difusa, y es permanente

El tag es la única forma de encontrar a alguien **a propósito** (§13). Una búsqueda por nombre
convertiría una app de apoyo entre iguales en un directorio de personas vulnerables.

## Los cuatro desenlaces

| Caso | Respuesta |
|---|---|
| No existe | `404 not_found` |
| **Bloqueo en cualquier dirección** | `404 not_found` — **el mismo cuerpo y el mismo código** |
| Tu propio tag | `422 own_tag` |
| Existe | `200` con la ficha y `follow_state` (`none` \| `pending` \| `following`) |

La decisión vive en `_shared/connect-lookup.ts`, que es puro y tiene los tests. **No está ahí por
ceremonia**: la regla «un tag con bloqueo responde igual que si no existiera» es una comparación
entre **dos** respuestas, y una comparación no se puede probar mirando una rama de un `if`. En el
módulo puro las dos son valores y el test las compara con `assertEquals` — si alguien añade mañana un
`{ kind: "not_found", reason: "blocked" }` para depurar, el test cae en vez de filtrarse.

Por eso el 404 sale de **una sola función** y no de dos literales iguales: dos literales que hoy
coinciden divergen el día que alguien edita uno, y aquí divergir es una fuga.

Un tag con **formato imposible** también es `404`, no un `400` de validación: mantener un solo
desenlace para «no lo vas a encontrar» evita que mañana alguien razone sobre dos.

## Lo que NO se promete

Las dos respuestas son idénticas en **cuerpo** y en **código**, no en **tiempo**. Un bloqueo hace una
consulta más que un tag inexistente, así que un atacante con muchas medidas podría distinguirlos por
latencia.

**No es deuda pendiente.** El [ADR 0028](../../../../../docs/decisions/0028-el-bloqueo-es-detectable-por-quien-lo-sufre.md)
(2026-08-30) decide **no cerrarlo**: el tiempo constante artificial encarece el backend entero y no
compra nada mientras siga abierto el oráculo **activo** —intentar escribir y ver que falla—, que es una
sola petición. `RN-23` protege el **contenido** de las respuestas, no la **capacidad de actuar**.

La mitigación que sí sale de ese ADR **ya está implementada**: un **tope de 30 búsquedas al día**
(`MAX_TAG_LOOKUPS_PER_DAY`), contado en `connect_tag_lookups` por el RPC `bump_tag_lookup`. No cierra
el canal temporal; lo acota por volumen —que es lo que un ataque de latencia necesita— y de paso
frena la enumeración de tags por fuerza bruta, que era el problema peor y no estaba anotado en
ninguna parte.

**El cupo cuenta PETICIONES, no búsquedas con éxito, y ese detalle es la mitad de la regla.** Si se
incrementara solo al fallar, el propio contador distinguiría un tag inexistente de uno encontrado, y
sería exactamente el oráculo que `RN-23` existe para cerrar. Por eso el incremento va **antes de
mirar el body**: lo que se paga es que una petición con el JSON roto también gasta cupo, y es el lado
correcto en el que equivocarse. Al agotarlo, `429 rate_limited` con su `retry_at` (`RN-21`) — **el
mismo exista el tag o no**.

**30 y no 5 como los refrescos del feed**: buscar un tag que alguien te ha pasado es la única forma
de encontrar a una persona a propósito, y no hay búsqueda difusa ni la habrá. Un tope estrecho aquí
no acotaría un ataque, rompería la función.

## POST y no GET con `?tag=`

El tag lleva `#` dentro (`alfon#K7M2QX9F`), que en una URL es el delimitador de fragmento. Un cliente
que se olvide de codificarlo mandaría solo `alfon`, y la búsqueda fallaría de una forma que **parece**
«no existe». En el body no existe ese borde.

## Verificado en vivo (2026-08-25)

Contra el stack local: el tag de alguien bloqueado y un tag inventado devolvieron el mismo `404` y el
mismo cuerpo **byte a byte**, en las dos direcciones del bloqueo; el propio tag dio `422 own_tag`; y
`follow_state` se comprobó **cambiando** (`none` → `following` al insertar el follow), porque un
valor constante y uno roto son el mismo byte.
