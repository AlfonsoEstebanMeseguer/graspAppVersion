# report-create

Trigger: HTTP (app). **Versión mínima de la Fase 4.** Persiste el reporte y ejecuta el mismo bloqueo que
`block-create` (`RN-25` de `docs/spec-contactos-mensajes-conectar.md`). Nada más.

Input: `{ reported_id, conversation_id? }` — `conversation_id` es opcional porque se podrá reportar desde
un perfil, sin conversación de por medio.

Efectos, y son exactamente dos:

1. Una fila en `public.reports` con `reporter_id`, `reported_id`, `conversation_id?` y `created_at`.
2. La misma lógica de bloqueo de `block-create` (`_shared/moderation.ts`): fila en `blocks` y
   `hidden = true` **solo en el lado del que reporta** (`RN-22`). No toca nada del lado del reportado
   —ni su `hidden`, ni su `cleared_at`, ni sus mensajes— porque el bloqueo nunca se revela (`RN-23`).

## Lo que esta función NO hace

Se enumera aquí a propósito: la versión anterior de este fichero prometía *«crea incidente, aplica delta
de reputación, evalúa sanción automática escalonada»*, que es la Fase 10 entera, y leerlo daba por hecha
una moderación que no existe.

- **Sin categoría ni justificación.** No hay formulario. La tabla `reports` tampoco tiene esas columnas:
  una columna que nadie escribe es una promesa falsa en el esquema.
- **Sin cola de moderación, sin panel de administración, sin revisión humana.** Nadie lee estos reportes
  todavía.
- **Sin reputación ni sanciones.** `reputation_events` y `sanctions` siguen sin existir.
- **Sin `report-undo`.** El reporte en sí no se retira. El bloqueo que esta función ejecuta **sí es
  reversible desde el ADR 0027**: se deshace con [`block-remove`](../block-remove/README.md), igual
  que si hubiera nacido de `block-create`. No hay forma de distinguir las dos filas en `blocks` ni
  motivo para tenerla, así que desbloquear a alguien reportado no retira su reporte — ver
  [`block-remove`](../block-remove/README.md#lo-que-no-hace).

Todo eso es Fase 10 — Secciones 8 y 17 del documento maestro. Lo pendiente, punto por punto, en
[`docs/pending-messaging.md`](../../../../../docs/pending-messaging.md).

## Retención

La retención de `reports` se revisará en la Fase 10, junto con la cola de moderación: es entonces cuando un
reporte pasa a ser **evidencia** y no solo una preferencia del usuario. Hoy las cuatro FKs de usuario
cascadean con la cuenta, porque un reporte sobre una cuenta ya borrada no tiene a quién moderar.

## Implementación (Tarea 14)

RN-25 —«reportar ejecuta automáticamente un bloqueo (mismo comportamiento)»— se cumple porque los
efectos **salen de la misma función** que usa `block-create` (`_shared/moderation.ts`), no porque
alguien se acuerde de copiarlos iguales. Un test lo fija comparando los dos resultados campo a campo
con el reporte quitado.

**El `conversation_id`, si viene, tiene que ser de quien reporta.** Sin esa comprobación cualquiera
podría colgar su reporte de la conversación de dos desconocidos: la FK no valida quién participa, y
cuando la Fase 10 construya la cola de moderación ese enlace es justo lo que un humano abriría para
leer el contexto — estaría leyendo la conversación de otras dos personas. Se responde 404, el mismo
cuerpo que si no existiera.

**Reportar es un evento; bloquear es un estado.** Reportar dos veces deja **dos filas** en `reports`
—dos hechos que la cola de la Fase 10 querrá ver por separado— y **un solo** bloqueo. Verificado.

**Orden de escritura**: el bloqueo primero, el reporte después. Al revés, un fallo en el bloqueo
devolvería 500, el cliente reintentaría y el reporte quedaría registrado dos veces. Detalle completo
en `applyModeration`.

## Verificado de punta a punta en local (2026-08-25)

Reportar desde un perfil **sin conversación** → fila con `conversation_id` NULL y el bloqueo
aplicado · reportar con la conversación de **otras dos personas** → 404 · reportar dos veces →
`reports=2`, `blocks` sin moverse · **el follow aceptado entre las dos personas sobrevivió al
reporte** (decisión 6: cortarlo sería observable) · reportarse a uno mismo → 400.

Estado: **implementado, sin desplegar.**

Contrato completo en `docs/api-contracts.md`.
