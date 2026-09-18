import {
  assertEquals,
  assertRejects,
  assertThrows,
} from "https://deno.land/std@0.208.0/assert/mod.ts";
import { AppError } from "./http.ts";
import {
  buildPhotoMap,
  EXPIRES_IN_SECONDS,
  MAX_USER_IDS,
  parseViewRequest,
  type ProfilePhotoRow,
  responseTypeFor,
} from "./photo-view.ts";

// Con letras hexadecimales (a-f) a propósito: si estas ids fueran solo dígitos,
// `U1.toUpperCase()` sería idéntico a `U1` y los tests de casing de más abajo no
// distinguirían nada — pasarían igual contra código que no normaliza casing.
const U1 = "aaaaaaaa-1111-4111-8111-111111111111";
const U2 = "bbbbbbbb-2222-4222-8222-222222222222";
const U3 = "cccccccc-3333-4333-8333-333333333333";
const EXPIRES_AT = "2026-08-12T10:05:00.000Z";

/** Firmador falso: determinista y sin red, para poder afirmar sobre la URL exacta. */
const fakeSign = (photoPath: string) => Promise.resolve(`https://r2.test/${photoPath}?firmada`);

function uuidList(n: number): string[] {
  return Array.from(
    { length: n },
    (_, i) => `${String(i).padStart(8, "0")}-1111-4111-8111-111111111111`,
  );
}

// --- parseViewRequest ------------------------------------------------------

Deno.test("parseViewRequest: lista valida devuelve las ids", () => {
  assertEquals(parseViewRequest({ user_ids: [U1, U2] }), [U1, U2]);
});

Deno.test("parseViewRequest: body que no es objeto es 400", () => {
  const err = assertThrows(() => parseViewRequest("hola"), AppError);
  assertEquals(err.status, 400);
});

Deno.test("parseViewRequest: body null es 400", () => {
  const err = assertThrows(() => parseViewRequest(null), AppError);
  assertEquals(err.status, 400);
});

Deno.test("parseViewRequest: array como body es 400", () => {
  const err = assertThrows(() => parseViewRequest([U1]), AppError);
  assertEquals(err.status, 400);
});

Deno.test("parseViewRequest: sin user_ids es 400", () => {
  const err = assertThrows(() => parseViewRequest({}), AppError);
  assertEquals(err.status, 400);
});

Deno.test("parseViewRequest: user_ids que no es array es 400", () => {
  const err = assertThrows(() => parseViewRequest({ user_ids: U1 }), AppError);
  assertEquals(err.status, 400);
});

Deno.test("parseViewRequest: lista vacia es 400", () => {
  const err = assertThrows(() => parseViewRequest({ user_ids: [] }), AppError);
  assertEquals(err.status, 400);
});

Deno.test("parseViewRequest: 50 ids es el maximo aceptado", () => {
  assertEquals(parseViewRequest({ user_ids: uuidList(MAX_USER_IDS) }).length, MAX_USER_IDS);
});

Deno.test("parseViewRequest: 51 ids es 400", () => {
  const err = assertThrows(
    () => parseViewRequest({ user_ids: uuidList(MAX_USER_IDS + 1) }),
    AppError,
  );
  assertEquals(err.status, 400);
});

Deno.test("parseViewRequest: un elemento que no es uuid es 400", () => {
  const err = assertThrows(() => parseViewRequest({ user_ids: [U1, "no-soy-uuid"] }), AppError);
  assertEquals(err.status, 400);
});

Deno.test("parseViewRequest: un elemento que no es string es 400", () => {
  const err = assertThrows(() => parseViewRequest({ user_ids: [U1, 42] }), AppError);
  assertEquals(err.status, 400);
});

Deno.test("parseViewRequest: ids duplicadas se deduplican", () => {
  assertEquals(parseViewRequest({ user_ids: [U1, U1, U2] }), [U1, U2]);
});

// Este test ES el contrato de seguridad D5: mandar una clave elegida por el cliente no firma nada.
Deno.test("parseViewRequest: un body con photo_path y sin user_ids es 400", () => {
  const err = assertThrows(
    () => parseViewRequest({ photo_path: `avatars/${U1}/abc.webp` }),
    AppError,
  );
  assertEquals(err.status, 400);
});

// --- buildPhotoMap ---------------------------------------------------------

Deno.test("buildPhotoMap: una fila con foto devuelve url firmada y expires_at", async () => {
  const rows: ProfilePhotoRow[] = [{ user_id: U1, photo_path: `avatars/${U1}/abc.webp` }];
  const photos = await buildPhotoMap([U1], rows, fakeSign, EXPIRES_AT);
  assertEquals(photos, {
    [U1]: {
      url: `https://r2.test/avatars/${U1}/abc.webp?firmada`,
      expires_at: EXPIRES_AT,
    },
  });
});

Deno.test("buildPhotoMap: una fila con photo_path null devuelve null", async () => {
  const rows: ProfilePhotoRow[] = [{ user_id: U1, photo_path: null }];
  assertEquals(await buildPhotoMap([U1], rows, fakeSign, EXPIRES_AT), { [U1]: null });
});

Deno.test("buildPhotoMap: una id pedida sin fila devuelve null", async () => {
  assertEquals(await buildPhotoMap([U1], [], fakeSign, EXPIRES_AT), { [U1]: null });
});

Deno.test("buildPhotoMap: toda id pedida aparece como clave", async () => {
  const rows: ProfilePhotoRow[] = [{ user_id: U2, photo_path: `avatars/${U2}/b.webp` }];
  const photos = await buildPhotoMap([U1, U2, U3], rows, fakeSign, EXPIRES_AT);
  assertEquals(Object.keys(photos).sort(), [U1, U2, U3].sort());
  assertEquals(photos[U1], null);
  assertEquals(photos[U3], null);
});

Deno.test("buildPhotoMap: una fila NO pedida no se cuela en la respuesta", async () => {
  const rows: ProfilePhotoRow[] = [
    { user_id: U1, photo_path: `avatars/${U1}/a.webp` },
    { user_id: U2, photo_path: `avatars/${U2}/b.webp` },
  ];
  const photos = await buildPhotoMap([U1], rows, fakeSign, EXPIRES_AT);
  assertEquals(Object.keys(photos), [U1]);
});

Deno.test("buildPhotoMap: solo firma las fotos que existen", async () => {
  const firmadas: string[] = [];
  const spySign = (p: string) => {
    firmadas.push(p);
    return Promise.resolve("https://r2.test/x");
  };
  const rows: ProfilePhotoRow[] = [
    { user_id: U1, photo_path: `avatars/${U1}/a.webp` },
    { user_id: U2, photo_path: null },
  ];
  await buildPhotoMap([U1, U2, U3], rows, spySign, EXPIRES_AT);
  assertEquals(firmadas, [`avatars/${U1}/a.webp`]);
});

Deno.test("buildPhotoMap: si el firmador falla, el error sube", async () => {
  const rows: ProfilePhotoRow[] = [{ user_id: U1, photo_path: `avatars/${U1}/a.webp` }];
  await assertRejects(
    () => buildPhotoMap([U1], rows, () => Promise.reject(new Error("R2 caido")), EXPIRES_AT),
    Error,
    "R2 caido",
  );
});

// F1: Postgres siempre serializa `uuid` en minúsculas. Una id pedida en mayúsculas debe seguir
// encontrando su fila, no caer en el "no tiene foto" silencioso.
Deno.test("buildPhotoMap: id pedida en mayusculas encuentra la fila en minusculas", async () => {
  const upper = U1.toUpperCase();
  const rows: ProfilePhotoRow[] = [{ user_id: U1, photo_path: `avatars/${U1}/a.webp` }];
  const photos = await buildPhotoMap([upper], rows, fakeSign, EXPIRES_AT);
  assertEquals(photos, {
    [upper]: { url: `https://r2.test/avatars/${U1}/a.webp?firmada`, expires_at: EXPIRES_AT },
  });
});

Deno.test("parseViewRequest: la misma id en dos casings se deduplica a una sola clave", () => {
  const upper = U1.toUpperCase();
  assertEquals(parseViewRequest({ user_ids: [U1, upper, U2] }), [U1, U2]);
});

// --- EXPIRES_IN_SECONDS ----------------------------------------------------

// El TTL no es un detalle de implementación: una URL firmada es un secreto portador y quien la
// tenga ve la foto sin pasar por ninguna autorización (`media-storage`: «minutos, no días»). Cinco
// minutos bastan para pintar una pantalla en una conexión mala y no dejan nada útil en el historial
// de nadie. Subirlo es una decisión de seguridad, no un ajuste — este test obliga a tomarla a
// propósito.
Deno.test("EXPIRES_IN_SECONDS son exactamente 5 minutos", () => {
  assertEquals(EXPIRES_IN_SECONDS, 300);
});

// --- responseTypeFor -------------------------------------------------------

// Estos tests guardan una defensa contra XSS almacenado, no un detalle de formato.
//
// El `Content-Type` con el que R2 guarda un objeto lo elige quien lo sube: el SDK saca
// `content-type` de la firma por defecto, así que se puede subir un polyglot RIFF/WEBP+HTML
// declarándolo `text/html`. `assertValidImageBytes` lo deja pasar —y con razón: mira los BYTES, y
// los bytes empiezan por una cabecera WEBP válida—. Sin `ResponseContentType`, R2 sirve ese objeto
// como HTML bajo una URL firmada que reparte la propia aplicación.
//
// Contra el código anterior estos tests no compilan siquiera: `responseTypeFor` no existía y el
// `GetObjectCommand` no llevaba ninguna cabecera de respuesta.
Deno.test("responseTypeFor: un .webp se sirve como imagen y en línea", () => {
  assertEquals(responseTypeFor(`avatars/${U1}/a.webp`), {
    ResponseContentType: "image/webp",
    ResponseContentDisposition: "inline",
  });
});

Deno.test("responseTypeFor: un .jpg se sirve como imagen y en línea", () => {
  assertEquals(responseTypeFor(`avatars/${U1}/a.jpg`), {
    ResponseContentType: "image/jpeg",
    ResponseContentDisposition: "inline",
  });
});

// El tipo sale de la EXTENSIÓN de la clave, que la acuña el servidor (`buildObjectKey`), nunca de
// lo que el cliente declaró al subir. Es toda la diferencia entre las dos fuentes de verdad.
Deno.test("responseTypeFor: una extensión desconocida se sirve inerte, no se adivina", () => {
  assertEquals(responseTypeFor(`avatars/${U1}/a.html`), {
    ResponseContentType: "application/octet-stream",
    ResponseContentDisposition: "attachment",
  });
});

Deno.test("responseTypeFor: sin extensión también se sirve inerte", () => {
  assertEquals(responseTypeFor(`avatars/${U1}/sin-extension`), {
    ResponseContentType: "application/octet-stream",
    ResponseContentDisposition: "attachment",
  });
});
