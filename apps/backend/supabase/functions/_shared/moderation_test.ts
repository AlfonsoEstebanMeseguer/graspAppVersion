import { assertEquals } from "https://deno.land/std@0.208.0/assert/mod.ts";
import {
  type ModerationAction,
  type ModerationContext,
  resolveModeration,
} from "./moderation.ts";
import { AppError } from "./http.ts";

const YO = "aaaaaaaa-0014-4000-8000-00000000000a"; // quien bloquea o reporta
const OTRO = "bbbbbbbb-0014-4000-8000-00000000000b"; // el bloqueado o reportado
const CONV = "cccccccc-0014-4000-8000-0000000000c1";
const AHORA = new Date("2026-08-25T12:00:00.000Z");

function ctx(over: Partial<ModerationContext> = {}): ModerationContext {
  return {
    action: "block",
    actorId: YO,
    targetId: OTRO,
    alreadyBlocked: false,
    conversationId: CONV,
    now: AHORA,
    ...over,
  };
}

function statusOf(fn: () => unknown): number {
  try {
    fn();
    return 0;
  } catch (err) {
    return err instanceof AppError ? err.status : -1;
  }
}

// =================================================================================================
// RN-22 — bloquear archiva la conversación, y solo en un lado
// =================================================================================================

Deno.test("RN-22: bloquear inserta la fila y archiva SOLO el lado del bloqueador", () => {
  const efectos = resolveModeration(ctx());

  assertEquals(efectos.insertBlock, true);
  assertEquals(efectos.stateWrites, [{ userId: YO, patch: { hidden: true } }]);
  assertEquals(efectos.insertReport, false);
});

Deno.test("sin conversación previa no hay nada que archivar", () => {
  // Se puede bloquear desde un perfil, sin haber hablado nunca.
  const efectos = resolveModeration(ctx({ conversationId: null }));

  assertEquals(efectos.insertBlock, true);
  assertEquals(efectos.stateWrites, []);
});

// =================================================================================================
// RN-23 — EL INVARIANTE: no se toca NADA del lado del bloqueado
// =================================================================================================

Deno.test("RN-23: NINGUNA acción escribe en la fila del bloqueado", () => {
  // El bloqueado conserva su conversación, su historial y su `hidden`. Si se le archivara o se le
  // vaciara algo, lo vería desaparecer y sabría que le han bloqueado — que es exactamente lo que
  // RN-23 prohíbe. Se recorre el enum entero: un test por acción se olvidaría de la que venga.
  const acciones: ModerationAction[] = ["block", "report", "unblock"];

  for (const action of acciones) {
    for (const alreadyBlocked of [false, true]) {
      const efectos = resolveModeration(ctx({ action, alreadyBlocked }));
      const ajenas = efectos.stateWrites.filter((w) => w.userId !== YO);
      assertEquals(ajenas, [], `\`${action}\` escribió en la fila del bloqueado`);
    }
  }
});

Deno.test("decisión 6: los efectos NO incluyen tocar follows, y este test lo fija", () => {
  // Cortar el follow al bloquear ES OBSERVABLE: si A bloquea a B y B deja de seguir a A de golpe,
  // B lo nota. Un follow que sobrevive es inocuo —el bloqueado no puede actuar— y no revela nada.
  //
  // Este test fija la FORMA de los efectos, así que añadir aquí un `deleteFollows` lo rompe a
  // propósito y obliga a quien lo intente a leer este comentario antes de seguir.
  const efectos = resolveModeration(ctx());

  assertEquals(
    Object.keys(efectos).sort(),
    ["deleteBlock", "insertBlock", "insertReport", "stateWrites"],
  );
});

// =================================================================================================
// RN-25 — reportar es bloquear, más la fila
// =================================================================================================

Deno.test("RN-25: reportar produce EXACTAMENTE los mismos efectos que bloquear, más el reporte", () => {
  const bloqueo = resolveModeration(ctx({ action: "block" }));
  const reporte = resolveModeration(ctx({ action: "report" }));

  assertEquals(reporte.insertReport, true);
  // Quitado el reporte, lo demás tiene que ser idéntico campo a campo. Si algún día divergieran,
  // reportar y bloquear tendrían efectos distintos y RN-25 dejaría de cumplirse en silencio.
  assertEquals({ ...reporte, insertReport: false }, bloqueo);
});

// =================================================================================================
// Idempotencia
// =================================================================================================

Deno.test("bloquear dos veces no duplica la fila de `blocks`", () => {
  const efectos = resolveModeration(ctx({ alreadyBlocked: true }));

  assertEquals(efectos.insertBlock, false);
});

Deno.test("pero SÍ vuelve a archivar, y es deliberado: hace la operación autocorrectiva", () => {
  // ESTO SE APARTA DE LA LETRA DEL PLAN, que decía «la segunda no duplica fila NI VUELVE A
  // ARCHIVAR». El motivo: el bloqueo son dos escrituras que NO comparten transacción (la fila de
  // `blocks` y el `hidden`), así que existe un fallo a medias —fila puesta, conversación sin
  // archivar—. Si el rearchivado dependiera de `alreadyBlocked`, ese estado sería ABSORBENTE:
  // ninguna llamada posterior lo arreglaría nunca, porque todas verían el bloqueo ya puesto.
  //
  // Volver a poner `hidden = true` sobre algo que ya lo está no tiene ningún efecto observable, así
  // que no se pierde nada de la idempotencia que el plan pedía — y se gana que un reintento repare.
  const efectos = resolveModeration(ctx({ alreadyBlocked: true }));

  assertEquals(efectos.stateWrites, [{ userId: YO, patch: { hidden: true } }]);
});

Deno.test("reportar a quien ya está bloqueado sigue registrando el reporte", () => {
  // Un reporte es un EVENTO, no un estado: dos reportes son dos hechos que la cola de moderación de
  // la Fase 10 querrá ver por separado. La mitad del bloqueo sí es idempotente.
  const efectos = resolveModeration(ctx({ action: "report", alreadyBlocked: true }));

  assertEquals(efectos.insertReport, true);
  assertEquals(efectos.insertBlock, false);
});

// =================================================================================================
// Validación
// =================================================================================================

Deno.test("bloquearse a uno mismo es un 400", () => {
  assertEquals(statusOf(() => resolveModeration(ctx({ targetId: YO }))), 400);
});

Deno.test("reportarse a uno mismo también", () => {
  assertEquals(statusOf(() => resolveModeration(ctx({ action: "report", targetId: YO }))), 400);
});

// =================================================================================================
// ADR 0027 — desbloquear
// =================================================================================================

Deno.test("desbloquear borra la fila y NO toca ninguna otra cosa", () => {
  const efectos = resolveModeration(ctx({ action: "unblock", alreadyBlocked: true }));

  assertEquals(efectos.deleteBlock, true);
  assertEquals(efectos.insertBlock, false);
  assertEquals(efectos.insertReport, false);
  // NO archiva ni desarchiva: `hidden` tambien lo pone «Eliminar historial» (RN-27), asi que
  // restaurarlo a ciegas desharia un archivado hecho por otro motivo. La conversacion reaparece
  // sola cuando alguien escriba, porque el trigger de entrega ya quita el `hidden`.
  assertEquals(efectos.stateWrites, []);
});

Deno.test("desbloquear a quien no estaba bloqueado es un no-op, no un error", () => {
  // El handler devuelve 200 igualmente: es lo que hace seguro el reintento, igual que en
  // `block-create`. Si esto lanzara, un reintento tras un fallo de red daria un error espurio.
  const efectos = resolveModeration(ctx({ action: "unblock", alreadyBlocked: false }));

  assertEquals(efectos.deleteBlock, false);
  assertEquals(efectos.stateWrites, []);
});

Deno.test("bloquear y reportar NO borran nunca la fila", () => {
  // El campo nuevo tiene que ser `false` en las dos acciones viejas. Sin esta asercion, un
  // `deleteBlock: true` colado en `block` pasaria inadvertido y bloquear desbloquearia.
  for (const action of ["block", "report"] as ModerationAction[]) {
    for (const alreadyBlocked of [false, true]) {
      const efectos = resolveModeration(ctx({ action, alreadyBlocked }));
      assertEquals(efectos.deleteBlock, false, `\`${action}\` puso deleteBlock a true`);
    }
  }
});

Deno.test("desbloquearse a uno mismo es un 400, como bloquearse", () => {
  assertEquals(statusOf(() => resolveModeration(ctx({ action: "unblock", targetId: YO }))), 400);
});
