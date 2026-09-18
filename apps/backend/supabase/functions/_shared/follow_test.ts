import { assertEquals, assertThrows } from "https://deno.land/std@0.208.0/assert/mod.ts";
import { AppError } from "./http.ts";
import {
  FOLLOW_REQUEST_WINDOW_MS,
  type FollowContext,
  MAX_FOLLOW_REQUESTS_PER_DAY,
  resolveFollowTransition,
} from "./follow.ts";

const A = "aaaaaaaa-0008-4000-8000-00000000000a"; // el solicitante
const B = "bbbbbbbb-0008-4000-8000-00000000000b"; // el destinatario
const AHORA = new Date("2026-08-25T12:00:00.000Z");

function ctx(over: Partial<FollowContext>): FollowContext {
  return {
    action: "request",
    actorId: A,
    targetId: B,
    existing: null,
    blocked: false,
    requestsToday: 0,
    oldestRequestAt: null,
    now: AHORA,
    ...over,
  };
}

// =================================================================================================
// request
// =================================================================================================

Deno.test("request: sin fila previa, inserta un pending y NO mueve contadores", () => {
  const t = resolveFollowTransition(ctx({}));
  assertEquals(t.kind, "insert");
  // Los contadores solo se mueven al pasar a `accepted` y al deshacerlo: una solicitud pendiente
  // no es un seguidor, y contarla inflaria el perfil de cualquiera que reparta solicitudes.
  assertEquals(t.counterDelta, 0);
});

Deno.test("request: sobre una solicitud ya pendiente es no-op", () => {
  const t = resolveFollowTransition(ctx({
    existing: { follower_id: A, followee_id: B, status: "pending" },
  }));
  assertEquals(t.kind, "noop");
});

Deno.test("request: sobre un follow ya aceptado es no-op", () => {
  const t = resolveFollowTransition(ctx({
    existing: { follower_id: A, followee_id: B, status: "accepted" },
  }));
  assertEquals(t.kind, "noop");
});

Deno.test("request: seguirse a uno mismo se rechaza", () => {
  assertThrows(() => resolveFollowTransition(ctx({ targetId: A })), AppError);
});

Deno.test("request: un no-op NO consume cupo aunque se este en el tope", () => {
  // Si el duplicado gastara cupo, pulsar dos veces el boton costaria dos solicitudes.
  const t = resolveFollowTransition(ctx({
    existing: { follower_id: A, followee_id: B, status: "pending" },
    requestsToday: MAX_FOLLOW_REQUESTS_PER_DAY,
  }));
  assertEquals(t.kind, "noop");
});

Deno.test("request: la solicitud 20 del dia SI pasa (el borde)", () => {
  const t = resolveFollowTransition(ctx({ requestsToday: MAX_FOLLOW_REQUESTS_PER_DAY - 1 }));
  assertEquals(t.kind, "insert");
});

Deno.test("request: la 21 se rechaza con 422 (RN-20)", () => {
  const err = assertThrows(
    () => resolveFollowTransition(ctx({ requestsToday: MAX_FOLLOW_REQUESTS_PER_DAY })),
    AppError,
  ) as AppError;
  assertEquals(err.status, 422);
  assertEquals(err.code, "rate_limited");
});

Deno.test("request: el 422 dice CUANDO se recupera (RN-21)", () => {
  const masAntigua = new Date(AHORA.getTime() - 3 * 60 * 60 * 1000).toISOString(); // hace 3 h
  const err = assertThrows(
    () =>
      resolveFollowTransition(ctx({
        requestsToday: MAX_FOLLOW_REQUESTS_PER_DAY,
        oldestRequestAt: masAntigua,
      })),
    AppError,
  ) as AppError;

  const details = err.details as { retry_at: string; limit: number };
  assertEquals(details.limit, MAX_FOLLOW_REQUESTS_PER_DAY);
  // El cupo se recupera cuando la MAS ANTIGUA sale de la ventana movil, no 24 h desde ahora.
  assertEquals(
    details.retry_at,
    new Date(new Date(masAntigua).getTime() + FOLLOW_REQUEST_WINDOW_MS).toISOString(),
  );
});

// =================================================================================================
// El bloqueo (RN-24) — y sobre todo, CÓMO se rechaza (RN-23)
// =================================================================================================

Deno.test("request: con bloqueo en cualquier direccion se rechaza (RN-24)", () => {
  assertThrows(() => resolveFollowTransition(ctx({ blocked: true })), AppError);
});

Deno.test("request: el rechazo por bloqueo es IDENTICO al de una cuenta inexistente (RN-23)", () => {
  // Es el corazon de RN-23: nada en la respuesta puede distinguir "te ha bloqueado" de "no existe".
  // Si estos dos errores divergieran —en codigo, en mensaje o en `details`— el bloqueado podria
  // deducir el bloqueo comparando respuestas.
  const porBloqueo = assertThrows(
    () => resolveFollowTransition(ctx({ blocked: true })),
    AppError,
  ) as AppError;
  const porInexistente = assertThrows(
    () => resolveFollowTransition(ctx({ existing: null, targetMissing: true })),
    AppError,
  ) as AppError;

  assertEquals(porBloqueo.status, porInexistente.status);
  assertEquals(porBloqueo.code, porInexistente.code);
  assertEquals(porBloqueo.message, porInexistente.message);
  assertEquals(porBloqueo.details, porInexistente.details);
});

Deno.test("accept: con bloqueo vigente NO se acepta (RN-17 no levanta un bloqueo)", () => {
  assertThrows(
    () =>
      resolveFollowTransition(ctx({
        action: "accept",
        actorId: B,
        targetId: A,
        existing: { follower_id: A, followee_id: B, status: "pending" },
        blocked: true,
      })),
    AppError,
  );
});

// =================================================================================================
// accept
// =================================================================================================

function aceptar(over: Partial<FollowContext> = {}) {
  return resolveFollowTransition(ctx({
    action: "accept",
    actorId: B,
    targetId: A,
    existing: { follower_id: A, followee_id: B, status: "pending" },
    ...over,
  }));
}

Deno.test("accept: pasa a accepted y suma 1 a los contadores", () => {
  const t = aceptar();
  assertEquals(t.kind, "accept");
  assertEquals(t.counterDelta, 1);
});

Deno.test("accept: es UNIDIRECCIONAL — la fila sigue siendo solicitante -> aceptante (RN-13)", () => {
  // El aceptante NO pasa a seguir al solicitante. Si la transicion invirtiera la direccion, o
  // devolviera dos filas, se estaria creando el follow inverso.
  const t = aceptar();
  assertEquals(t.kind === "accept" && t.followerId, A);
  assertEquals(t.kind === "accept" && t.followeeId, B);
});

Deno.test("accept: reanuda una conversacion ignorada (RN-17)", () => {
  assertEquals(aceptar().resumesIgnoredConversation, true);
});

Deno.test("accept: sobre un follow ya aceptado es no-op (idempotente)", () => {
  const t = aceptar({ existing: { follower_id: A, followee_id: B, status: "accepted" } });
  assertEquals(t.kind, "noop");
});

Deno.test("accept: sin solicitud que aceptar se rechaza", () => {
  assertThrows(() => aceptar({ existing: null }), AppError);
});

// =================================================================================================
// reject — RN-16, que es justo lo contrario de RN-07
// =================================================================================================

Deno.test("reject: BORRA la fila, no la marca como rechazada (RN-16)", () => {
  // Un follow rechazado puede volver a solicitarse, a diferencia del primer mensaje (RN-07). Si
  // esto guardara un estado 'rejected', esa segunda solicitud seria imposible.
  const t = resolveFollowTransition(ctx({
    action: "reject",
    actorId: B,
    targetId: A,
    existing: { follower_id: A, followee_id: B, status: "pending" },
  }));
  assertEquals(t.kind, "delete");
  assertEquals(t.counterDelta, 0); // estaba pendiente: no habia contador que deshacer
});

Deno.test("reject + request: tras rechazar se puede volver a solicitar (RN-16)", () => {
  const rechazo = resolveFollowTransition(ctx({
    action: "reject",
    actorId: B,
    targetId: A,
    existing: { follower_id: A, followee_id: B, status: "pending" },
  }));
  assertEquals(rechazo.kind, "delete");

  // Tras el borrado, el estado que ve la siguiente solicitud es `existing: null`.
  assertEquals(resolveFollowTransition(ctx({ existing: null })).kind, "insert");
});

// =================================================================================================
// unfollow y remove_follower
// =================================================================================================

Deno.test("unfollow: sobre un follow aceptado borra y RESTA 1", () => {
  const t = resolveFollowTransition(ctx({
    action: "unfollow",
    existing: { follower_id: A, followee_id: B, status: "accepted" },
  }));
  assertEquals(t.kind, "delete");
  assertEquals(t.counterDelta, -1);
});

Deno.test("unfollow: sobre una solicitud pendiente la cancela SIN tocar contadores", () => {
  const t = resolveFollowTransition(ctx({
    action: "unfollow",
    existing: { follower_id: A, followee_id: B, status: "pending" },
  }));
  assertEquals(t.kind, "delete");
  assertEquals(t.counterDelta, 0);
});

Deno.test("unfollow: NO toca ninguna conversacion (RN-15)", () => {
  // Dejar de seguir no afecta a conversaciones ya aceptadas. La transicion no puede llevar
  // ningun efecto sobre conversaciones, o el handler lo aplicaria.
  const t = resolveFollowTransition(ctx({
    action: "unfollow",
    existing: { follower_id: A, followee_id: B, status: "accepted" },
  }));
  assertEquals(t.resumesIgnoredConversation, false);
});

Deno.test("remove_follower: borra la fila del OTRO sentido y resta 1", () => {
  // Aqui el actor es el seguido (B) y quita a su seguidor (A): la fila es A -> B.
  const t = resolveFollowTransition(ctx({
    action: "remove_follower",
    actorId: B,
    targetId: A,
    existing: { follower_id: A, followee_id: B, status: "accepted" },
  }));
  assertEquals(t.kind, "delete");
  assertEquals(t.kind === "delete" && t.followerId, A);
  assertEquals(t.kind === "delete" && t.followeeId, B);
  assertEquals(t.counterDelta, -1);
});

Deno.test("unfollow: sin fila que borrar se rechaza", () => {
  assertThrows(
    () => resolveFollowTransition(ctx({ action: "unfollow", existing: null })),
    AppError,
  );
});

// =================================================================================================
// Constantes
// =================================================================================================

Deno.test("MAX_FOLLOW_REQUESTS_PER_DAY: son 20 (RN-20)", () => {
  assertEquals(MAX_FOLLOW_REQUESTS_PER_DAY, 20);
});

Deno.test("FOLLOW_REQUEST_WINDOW_MS: ventana movil de 24 h", () => {
  assertEquals(FOLLOW_REQUEST_WINDOW_MS, 86_400_000);
});
