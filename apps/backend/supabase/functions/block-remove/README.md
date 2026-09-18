# block-remove

Deshace un bloqueo. Contrapartida de [`block-create`](../block-create/README.md).

`POST` · `{ "target_id": "<uuid>" }` → `{ "success": true, "blocked": false }`

**200 tanto si había fila como si no**, con el mismo cuerpo: es lo que hace seguro el reintento.
`404` si el usuario no existe, `400` si el uuid es inválido o si te desbloqueas a ti mismo.

## Lo que revela, que es el motivo de que haya un ADR

Desbloquear deja que la otra persona vuelva a encontrarte por tag, a verte en Conectar y a
escribirte, así que **puede deducir que la habías bloqueado**. `RN-23` protege a quien bloquea de
que su decisión se sepa; deshacerla es un acto suyo, y puede renunciar a esa protección. **El modal
de la app está obligado a decírselo antes de confirmar** — es la única información con la que
decide.

Lo que `RN-23` sigue prohibiendo y esto no toca: que un bloqueo **vigente** se distinga de un cupo
agotado. Ver [ADR 0027](../../../../../docs/decisions/0027-el-bloqueo-deja-de-ser-irreversible.md).

## Lo que NO hace

- **No toca `conversation_states`.** `hidden` también lo pone «Eliminar historial» (`RN-27`), así
  que restaurarlo a ciegas desharía un archivado hecho por otro motivo. La conversación reaparece
  sola cuando alguien escriba: el trigger de entrega ya quita el `hidden`.
- **No restaura follows**: bloquear nunca cortó ninguno.
- **No deja rastro** de que el bloqueo existió. La fila se borra. Nadie lee ese dato hoy.
- **No retira el reporte.** Un bloqueo nacido de `report-create` se deshace igual —no hay forma de
  distinguir las dos filas ni motivo para tenerla—, pero la fila de `reports` es un evento y se
  queda.

Lo pendiente, punto por punto, en [`docs/pending-messaging.md`](../../../../../docs/pending-messaging.md).
