// La cadena de 4 avatares de la tarjeta de sala (ADR 0032 § 4).
//
// LO QUE ESTOS TESTS FIJAN es el orden y a quién se excluye. El host NO entra
// en la cadena porque ya sale en grande a la izquierda: repetirlo gastaría uno
// de los cuatro huecos en información que el usuario ya tiene.
import { assertEquals } from "jsr:@std/assert@1";
import { type CardParticipant, MAX_OCCUPANTS, MAX_SPEAKERS, pickCardAvatars } from "./rooms.ts";

const HOST = "host-id";

function p(userId: string, role: CardParticipant["role"], joinedAt: string): CardParticipant {
  return { userId, role, joinedAt };
}

Deno.test("los topes son los decididos el 2026-08-31", () => {
  assertEquals(MAX_OCCUPANTS, 20);
  assertEquals(MAX_SPEAKERS, 2);
});

Deno.test("el host nunca entra en la cadena", () => {
  const { shown } = pickCardAvatars(
    [p(HOST, "host", "2026-09-01T10:00:00Z"), p("a", "listener", "2026-09-01T10:05:00Z")],
    HOST,
  );
  assertEquals(shown.map((x) => x.userId), ["a"]);
});

Deno.test("el hablante del escenario va antes que los oyentes recientes", () => {
  // Entrada: listener reciente DELANTE del speaker — solo pasa si se ordena por rol
  const { shown } = pickCardAvatars([
    p(HOST, "host", "2026-09-01T10:00:00Z"),
    p("recien-llegado", "listener", "2026-09-01T10:59:00Z"),
    p("viejo-hablante", "speaker", "2026-09-01T10:01:00Z"),
  ], HOST);
  assertEquals(shown.map((x) => x.userId), ["viejo-hablante", "recien-llegado"]);
});

Deno.test("entre oyentes gana el ultimo en entrar", () => {
  const { shown } = pickCardAvatars([
    p("a", "listener", "2026-09-01T10:01:00Z"),
    p("b", "listener", "2026-09-01T10:03:00Z"),
    p("c", "listener", "2026-09-01T10:02:00Z"),
  ], HOST);
  assertEquals(shown.map((x) => x.userId), ["b", "c", "a"]);
});

Deno.test("el overflow cuenta los que NO caben, no el total", () => {
  const participantes = Array.from({ length: 12 }, (_, i) =>
    p(`u${i}`, "listener", `2026-09-01T10:${String(i).padStart(2, "0")}:00Z`));
  const { shown, overflow } = pickCardAvatars(participantes, HOST);
  assertEquals(shown.length, 4);
  assertEquals(overflow, 8);
});

Deno.test("con 4 o menos no hay overflow", () => {
  const { shown, overflow } = pickCardAvatars(
    [p("a", "listener", "2026-09-01T10:01:00Z")],
    HOST,
  );
  assertEquals(shown.length, 1);
  assertEquals(overflow, 0);
});

Deno.test("entre dos hablantes gana el más reciente", () => {
  const { shown } = pickCardAvatars([
    p("speaker-viejo", "speaker", "2026-09-01T10:01:00Z"),
    p("speaker-nuevo", "speaker", "2026-09-01T10:59:00Z"),
  ], HOST);
  assertEquals(shown.map((x) => x.userId), ["speaker-nuevo", "speaker-viejo"]);
});

Deno.test("la entrada en orden inverso al esperado se reordena", () => {
  // Entrada: x (10:03), y (10:04), z (10:05) — orden ascendente
  // Esperado: ["z", "y", "x"] — orden descendente por recencia
  // Esto falla si se devuelve el array sin ordenar.
  const { shown } = pickCardAvatars([
    p("x", "listener", "2026-09-01T10:03:00Z"),
    p("y", "listener", "2026-09-01T10:04:00Z"),
    p("z", "listener", "2026-09-01T10:05:00Z"),
  ], HOST);
  assertEquals(shown.map((x) => x.userId), ["z", "y", "x"]);
});

Deno.test("un joinedAt inválido se empuja al final", () => {
  const { shown } = pickCardAvatars([
    p("valid-old", "listener", "2026-09-01T10:01:00Z"),
    p("invalid", "listener", "not-a-date"),
    p("valid-new", "listener", "2026-09-01T10:05:00Z"),
  ], HOST);
  // El inválido debe ir al final (después de los válidos ordenados)
  assertEquals(shown.map((x) => x.userId), ["valid-new", "valid-old", "invalid"]);
});
