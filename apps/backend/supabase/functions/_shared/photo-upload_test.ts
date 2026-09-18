import { assertEquals, assertThrows } from "https://deno.land/std@0.208.0/assert/mod.ts";
import { AppError } from "./http.ts";
import {
  buildObjectKey,
  EXPIRES_IN,
  MAX_FILE_SIZE,
  parseUploadRequest,
} from "./photo-upload.ts";

const USER = "da2de860-429c-4b9f-8458-feb74d6b5a6a";
const UUID = "8f14e45f-ceea-4067-a0ba-8f14e45fceea";

function status(fn: () => unknown): number {
  return assertThrows(fn, AppError).status;
}

// --- parseUploadRequest -----------------------------------------------------

Deno.test("parseUploadRequest: webp valido devuelve el formato", () => {
  assertEquals(parseUploadRequest({ file_size: 1024, mime_type: "image/webp" }), {
    fileSize: 1024,
    format: "webp",
  });
});

// ESTE es el test de 0012: antes, un jpeg declarado se aceptaba y luego se firmaba como webp.
Deno.test("parseUploadRequest: jpeg se acepta Y SE CONSERVA como jpeg", () => {
  assertEquals(parseUploadRequest({ file_size: 1024, mime_type: "image/jpeg" }), {
    fileSize: 1024,
    format: "jpeg",
  });
});

Deno.test("parseUploadRequest: png ya no se admite", () => {
  assertEquals(status(() => parseUploadRequest({ file_size: 1024, mime_type: "image/png" })), 400);
});

Deno.test("parseUploadRequest: body que no es objeto es 400", () => {
  assertEquals(status(() => parseUploadRequest("hola")), 400);
  assertEquals(status(() => parseUploadRequest(null)), 400);
});

Deno.test("parseUploadRequest: sin file_size es 400", () => {
  assertEquals(status(() => parseUploadRequest({ mime_type: "image/webp" })), 400);
});

Deno.test("parseUploadRequest: file_size no positivo es 400", () => {
  for (const size of [0, -1, -1024]) {
    assertEquals(status(() => parseUploadRequest({ file_size: size, mime_type: "image/webp" })), 400);
  }
});

Deno.test("parseUploadRequest: file_size que no es numero es 400", () => {
  assertEquals(status(() => parseUploadRequest({ file_size: "1024", mime_type: "image/webp" })), 400);
});

Deno.test("parseUploadRequest: exactamente 200 KB se acepta", () => {
  assertEquals(
    parseUploadRequest({ file_size: MAX_FILE_SIZE, mime_type: "image/webp" }).fileSize,
    MAX_FILE_SIZE,
  );
});

Deno.test("parseUploadRequest: un byte por encima de 200 KB es 400", () => {
  assertEquals(
    status(() => parseUploadRequest({ file_size: MAX_FILE_SIZE + 1, mime_type: "image/webp" })),
    400,
  );
});

Deno.test("parseUploadRequest: sin mime_type es 400", () => {
  assertEquals(status(() => parseUploadRequest({ file_size: 1024 })), 400);
});

Deno.test("parseUploadRequest: mime_type que no es string es 400", () => {
  assertEquals(status(() => parseUploadRequest({ file_size: 1024, mime_type: 42 })), 400);
});

// --- buildObjectKey ---------------------------------------------------------

Deno.test("buildObjectKey: la extension sale del formato, no es fija", () => {
  assertEquals(buildObjectKey(USER, "webp", UUID), `avatars/${USER}/${UUID}.webp`);
  assertEquals(buildObjectKey(USER, "jpeg", UUID), `avatars/${USER}/${UUID}.jpg`);
});

// La clave tiene que caer bajo el prefijo que `assertPathOwnership` exige, o la confirmación
// devolvería 403 sobre una subida legítima.
Deno.test("buildObjectKey: la clave cae bajo el prefijo del usuario", () => {
  assertEquals(buildObjectKey(USER, "jpeg", UUID).startsWith(`avatars/${USER}/`), true);
});

// La ventana de la URL de subida ES la superficie de ataque, no un ajuste de comodidad. La
// validación de bytes (decisión 0013) ocurre al CONFIRMAR, así que mientras la URL siga viva se
// puede repetir el PUT y dejar en `photo_path` bytes que nadie miró; `photo_audit_log` guarda la
// ruta y no un hash, así que el cambiazo no deja rastro. Eran 3600 s.
//
// 120 s no cierra el fallo, lo estrecha. Subirlo otra vez es una decisión de seguridad y este test
// obliga a tomarla mirándola de frente.
Deno.test("EXPIRES_IN son 2 minutos, no una hora", () => {
  assertEquals(EXPIRES_IN, 120);
});

Deno.test("MAX_FILE_SIZE son 200 KB", () => {
  assertEquals(MAX_FILE_SIZE, 200 * 1024);
});
