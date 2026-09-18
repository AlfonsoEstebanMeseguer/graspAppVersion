import { assertEquals, assertThrows } from "https://deno.land/std@0.208.0/assert/mod.ts";
import { AppError } from "./http.ts";
import { assertPathOwnership, parseAvatarRequest, PRESET_AVATARS } from "./avatar-set.ts";

const USER = "da2de860-429c-4b9f-8458-feb74d6b5a6a";
const OTHER = "0d15ea5e-1111-4111-8111-111111111111";
const PATH = `avatars/${USER}/8f14e45f-ceea-4067-a0ba-8f14e45fceea.webp`;

function status(fn: () => unknown): number {
  return assertThrows(fn, AppError).status;
}

// --- parseAvatarRequest: el camino de la foto -------------------------------

Deno.test("parseAvatarRequest: photo_path solo devuelve kind photo", () => {
  assertEquals(parseAvatarRequest({ photo_path: PATH }), { kind: "photo", photoPath: PATH });
});

Deno.test("parseAvatarRequest: photo_path con extension no admitida es 400", () => {
  assertEquals(status(() => parseAvatarRequest({ photo_path: `avatars/${USER}/x.png` })), 400);
});

// ADR 0012: una subida en JPEG produce una clave .jpg, y confirmarla tiene que funcionar. Antes
// esta función exigía .webp, así que la foto se quedaba subida y sin confirmar — huérfana.
Deno.test("parseAvatarRequest: photo_path .jpg es valido", () => {
  const jpgPath = `avatars/${USER}/8f14e45f-ceea-4067-a0ba-8f14e45fceea.jpg`;
  assertEquals(parseAvatarRequest({ photo_path: jpgPath }), {
    kind: "photo",
    photoPath: jpgPath,
  });
});

Deno.test("parseAvatarRequest: .png y .jpeg siguen sin ser validos", () => {
  for (const ext of [".png", ".jpeg", ".gif", ""]) {
    assertEquals(
      status(() => parseAvatarRequest({ photo_path: `avatars/${USER}/x${ext}` })),
      400,
      `deberia rechazar '${ext}'`,
    );
  }
});

Deno.test("parseAvatarRequest: photo_path vacio es 400", () => {
  assertEquals(status(() => parseAvatarRequest({ photo_path: "" })), 400);
});

Deno.test("parseAvatarRequest: photo_path que no es string es 400", () => {
  assertEquals(status(() => parseAvatarRequest({ photo_path: 42 })), 400);
});

// --- parseAvatarRequest: el camino del preset -------------------------------

Deno.test("parseAvatarRequest: preset solo devuelve kind preset", () => {
  assertEquals(parseAvatarRequest({ preset: "gym" }), { kind: "preset", preset: "gym" });
});

Deno.test("parseAvatarRequest: los 8 presets del dominio se aceptan", () => {
  for (const preset of PRESET_AVATARS) {
    assertEquals(parseAvatarRequest({ preset }), { kind: "preset", preset });
  }
});

Deno.test("parseAvatarRequest: un preset fuera del dominio es 400", () => {
  assertEquals(status(() => parseAvatarRequest({ preset: "hacker" })), 400);
});

// El `check` de la migracion ya lo rechazaria, pero como un 500 por violacion de constraint.
// Este caso existe para que el cliente reciba un 400 legible, y para dejar escrito que una ruta
// NUNCA es un preset valido.
Deno.test("parseAvatarRequest: una clave de R2 como preset es 400, no un preset", () => {
  assertEquals(status(() => parseAvatarRequest({ preset: PATH })), 400);
});

Deno.test("parseAvatarRequest: preset que no es string es 400", () => {
  assertEquals(status(() => parseAvatarRequest({ preset: ["gym"] })), 400);
});

// --- parseAvatarRequest: exactamente uno ------------------------------------

Deno.test("parseAvatarRequest: mandar los dos es 400", () => {
  assertEquals(status(() => parseAvatarRequest({ photo_path: PATH, preset: "gym" })), 400);
});

Deno.test("parseAvatarRequest: no mandar ninguno es 400", () => {
  assertEquals(status(() => parseAvatarRequest({})), 400);
});

Deno.test("parseAvatarRequest: body que no es objeto es 400", () => {
  assertEquals(status(() => parseAvatarRequest("gym")), 400);
});

Deno.test("parseAvatarRequest: body null es 400", () => {
  assertEquals(status(() => parseAvatarRequest(null)), 400);
});

Deno.test("parseAvatarRequest: body array es 400", () => {
  assertEquals(status(() => parseAvatarRequest([{ preset: "gym" }])), 400);
});

// --- assertPathOwnership ----------------------------------------------------
// Vivia sin tests dentro del index.ts. Es la comprobacion que impide reclamar la clave de otro.

Deno.test("assertPathOwnership: la clave propia pasa", () => {
  assertPathOwnership(PATH, USER);
});

Deno.test("assertPathOwnership: la clave de OTRO usuario es 403", () => {
  assertEquals(status(() => assertPathOwnership(`avatars/${OTHER}/x.webp`, USER)), 403);
});

Deno.test("assertPathOwnership: otro prefijo de primer nivel es 403", () => {
  assertEquals(status(() => assertPathOwnership(`voice/${USER}/x.webp`, USER)), 403);
});

// El prefijo se comprueba con startsWith, asi que sin la barra final `avatars/<user>malicioso/`
// pasaria por ser del usuario. La barra la pone el propio codigo, pero conviene fijarlo.
Deno.test("assertPathOwnership: un user_id que solo EMPIEZA igual es 403", () => {
  assertEquals(status(() => assertPathOwnership(`avatars/${USER}-otro/x.webp`, USER)), 403);
});
