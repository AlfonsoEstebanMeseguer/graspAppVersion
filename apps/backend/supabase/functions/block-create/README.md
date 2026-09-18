# block-create

Trigger: HTTP (app), `POST /functions/v1/block-create`. Bloquear a alguien (§2.5, RN-22 a RN-24,
RN-07). Fase 4, Tarea 14.

Requiere `service_role`: **sí**. `blocks` no tiene ninguna policy de escritura, y es deliberado:
**bloquear no es insertar una fila**, tiene efectos en otra tabla (archivar la conversación del
bloqueador, RN-22). Si el cliente pudiera insertar directo, existiría un bloqueo a medias por diseño.

## Se llama `create`, no `toggle`, y eso sigue siendo deliberado

Cuando se escribió era porque **no había desbloqueo** (decisión 6 del plan). Desde el ADR 0027 sí lo
hay, y vive en [`block-remove`](../block-remove/README.md) — una función aparte, no un `toggle`,
porque un toggle esconde en qué dirección acabaste sobre una operación cuyo efecto observable depende
del estado previo. El par `create` + `remove` mantiene la propiedad que buscaba el nombre original:
cada uno dice exactamente lo que hace.

Lo pendiente, punto por punto, en [`docs/pending-messaging.md`](../../../../../docs/pending-messaging.md).

## Qué hace, y qué no toca

| | |
|---|---|
| Inserta en `blocks` | RN-24: el bloqueado no puede escribir, abrir conversación ni mandar solicitud |
| `hidden = true` **solo en el lado del bloqueador** | RN-22 |
| **No toca nada del lado del bloqueado** | RN-23: conserva conversación, historial y `cleared_at` |
| **No corta ningún follow**, en ninguna dirección | decisión 6 |

**Por qué los follows sobreviven, que parece un olvido y no lo es.** Cortarlos es **observable**: si A
bloquea a B y B deja de seguir a A de golpe, B lo nota, y RN-23 dice que el bloqueo no se revela
nunca. Un follow que sobrevive es inocuo porque el bloqueado no puede actuar. Hay un test que fija la
**forma** de `ModerationEffects` para que añadir ahí un `deleteFollows` rompa algo a propósito.

## 200 tanto si bloqueó como si ya estaba bloqueado

Con el **mismo cuerpo**. Distinguir los dos casos le diría a quien llama algo sobre el estado previo,
y el estado previo de un bloqueo no es información que deba viajar. El cliente no necesita saberlo:
quería que esa persona quedara bloqueada, y lo está.

## El orden de las escrituras es la garantía ante reintentos

Las tres escrituras posibles —la fila de `blocks`, el archivado y (en `report-create`) la fila de
`reports`— **no comparten transacción**: PostgREST son tres llamadas. La atomicidad real exigiría una
función SQL. Se acepta a sabiendas, y el orden acota el daño:

1. **`blocks` primero**, que es la mitad **protectora**. Si algo falla después, lo hecho es lo que
   protege y lo que falta es archivar, que es cosmético.
2. **El archivado después, y sin depender de si ya estaba bloqueado.** Aquí hay un aparte deliberado
   del plan, que decía «la segunda no duplica fila **ni vuelve a archivar**»: si el rearchivado
   dependiera de `alreadyBlocked`, un fallo a medias sería un estado **absorbente** —ninguna llamada
   posterior lo arreglaría, porque todas verían el bloqueo ya puesto—. Poner `hidden = true` sobre
   algo que ya lo está no tiene efecto observable, así que no se pierde nada de la idempotencia que
   el plan pedía y se gana que un reintento **repare**.
3. Por lo mismo, un fallo devuelve **500 y no un 200 optimista**: es el 500 el que provoca el
   reintento que repara.

## Errores

`400` `target_id` no uuid, o bloquearse a uno mismo · `401` · `404` el usuario no existe · `405` ·
`500`.

## Verificado de punta a punta en local (2026-08-25)

Sobre una conversación **aceptada con historial**: tras bloquear, la bandeja del bloqueador queda
vacía y la del bloqueado **intacta** (RN-22) · el hilo del bloqueado conserva **sus dos mensajes** y
el input inerte con el texto neutro del ADR 0022 (RN-23) · el bloqueado recibe `send_blocked` al
escribir y un `not_found` opaco al mandar solicitud de seguimiento (RN-24) · bloquear dos veces
devuelve el mismo cuerpo y deja `blocks` en 1 · bloquearse a uno mismo → 400 · **el follow aceptado
sobrevivió** al bloqueo.

Estado: **implementado, sin desplegar.**
