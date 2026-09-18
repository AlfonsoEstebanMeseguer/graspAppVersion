# messaging-search

Trigger: HTTP (app), `GET /functions/v1/messaging-search?conversation_id=<uuid>&q=<término>`.
La búsqueda dentro de una conversación (§9.4). Fase 4, Tarea 13.

Requiere `service_role`: **sí**, como el resto de la mensajería.

## Por qué se busca en Deno y no con un `ilike`

§9.4 pide una búsqueda insensible a mayúsculas **y a acentos**, y además el **resaltado del término
dentro de la burbuja**. Un `ilike` daría lo primero y nada de lo segundo: el cliente tendría que
volver a buscar sobre el texto para saber dónde resaltar, y ahí está la trampa — **dos
normalizaciones distintas a cada lado desplazan el resaltado**. Se calcula una vez, aquí, y viajan
los offsets.

La lógica es pura y vive en `_shared/text-search.ts`, con 16 tests y cinco mutaciones comprobadas.

## Los offsets son del texto ORIGINAL, y eso es todo el módulo

Normalizar puede **acortar** la cadena: un texto ya descompuesto pierde sus acentos combinantes al
normalizarse (11 unidades pasan a 10). Un offset calculado sobre el texto normalizado señalaría el
sitio equivocado, y se desviaría más cuantos más acentos hubiera antes de la coincidencia.

Por eso se normaliza carácter a carácter llevando un mapa de vuelta al original. Dos consecuencias
que tienen su test:

- **Se cuentan unidades UTF-16**, que es como indexan `slice` y las cadenas de Dart. Contando puntos
  de código, el resaltado en Flutter saldría corrido en cuanto hubiera un emoji antes.
- **Una coincidencia que acaba en un acento descompuesto se lo traga.** «café» descompuesto es
  `c-a-f-e-´`: el final «natural» caería en la `e` y el cliente pintaría *cafe* resaltado con una
  tilde suelta sin resaltar justo encima.

El primitivo NFD **se comparte** con `toSlug` (`_shared/validation.ts`), no se duplica: dos copias
podrían divergir, y divergir aquí significa que el resaltado cae donde el backend no dijo.

## El guardia de la búsqueda vacía es load-bearing

Un término de solo espacios o un acento suelto normaliza a `""`, y `indexOf("")` devuelve la
posición de partida **siempre**. Sin el guardia, el bucle no termina.

> **Comprobado, y con una sorpresa de método.** Al mutar el módulo para quitar el guardia, el proceso
> no dejó ningún test en rojo: **murió por OOM a 4 GB** acumulando coincidencias. Como el detector de
> mutaciones solo buscaba líneas `... FAILED`, lo leyó como «esta mutación no rompe nada» — un falso
> negativo de la misma familia que el de los códigos de color ANSI. **Una mutación que no produce
> `FAILED` no está probada: hay que mirar la salida entera.**

## Por qué 1000 mensajes

Es la enmienda nº 4 de la spec: cota por **tamaño**, no por tiempo.

- **Determinista**: da el mismo resultado hoy y dentro de un año.
- Se resuelve con el índice `direct_messages (conversation_id, created_at desc)` que la paginación
  necesita igualmente.
- **Acota lo transferido a ~1 MB por búsqueda** (1000 mensajes × los 1000 caracteres de RN-26), que
  es la razón real de la cota.

Una cota por tiempo, en cambio, vaciaría la búsqueda de una conversación antigua sin que el usuario
entienda por qué.

## La visibilidad no se reimplementa

§9.4 exige no buscar en mensajes borrados para el usuario actual, ni anteriores a su `cleared_at`,
ni en lápidas. Las tres reglas ya viven en `projectMessages` (`_shared/messaging-view.ts`, Tarea 11),
así que **se reutiliza**. Escribirlas otra vez aquí sería una segunda copia de las mismas reglas
esperando a divergir.

## Salida

```jsonc
{
  "total": 5,                  // coincidencias TOTALES: el `12` del contador `3/12`
  "searched_messages": 4,      // los realmente mirados (sin lápidas): la cabecera dice la verdad
  "search_limit": 1000,
  "matches": [                 // de más reciente a más antiguo
    { "message_id": "<uuid>", "created_at": "…", "offsets": [{ "start": 0, "end": 7 }] }
  ]
}
```

`total` cuenta **coincidencias**, no mensajes: un mensaje con la palabra tres veces aporta tres
saltos a las flechas arriba/abajo del §9.4.

## Errores

`400` `conversation_id` no uuid, o `q` fuera de 1-100 · `401` · `404` no existe **o no participas** ·
`405` · `500`.

> **404 y no el 403 que decía el paso 3 del plan.** Un 403 distinguiría «existe pero no es tuya» de
> «no existe», que es un enumerador de conversaciones ajenas. Las Tareas 11 y 12 ya devuelven 404 en
> el mismo caso; dejar aquí un 403 reabriría por una puerta lo que las otras dos cierran, y la
> búsqueda es tan buen oráculo como el hilo — con offsets, además.

## Verificado de punta a punta en local (2026-08-25)

Buscar `cancion` y `canción` devuelve **exactamente lo mismo**, en los dos sentidos · offsets
cayendo sobre el texto original (`Mi canción favorita` → 3-10) · tres coincidencias en un mismo
mensaje sin solaparse · no participante → 404 · `q` en blanco → 400 · y los tres filtros del §9.4
**por espectador**: tras un `delete_for_me` de Ben, él pasa de 5 a 4 y Ana sigue en 5; tras una
lápida, Ana baja a 2; tras el `delete_history` de Ben, él queda en 0 y Ana intacta.

Estado: **implementado, sin desplegar.**
