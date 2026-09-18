import { assertEquals, assertThrows } from "https://deno.land/std@0.208.0/assert/mod.ts";
import { AppError } from "./http.ts";
import {
  ALLOWED_MIME_TYPES,
  assertValidImageBytes,
  extensionForFormat,
  formatFromMime,
  formatFromPath,
  formatMime,
  MAX_DIMENSION,
  readDimensions,
  sniffFormat,
} from "./image-format.ts";

// --- la tabla ---------------------------------------------------------------

Deno.test("ALLOWED_MIME_TYPES son exactamente webp y jpeg", () => {
  assertEquals([...ALLOWED_MIME_TYPES].sort(), ["image/jpeg", "image/webp"]);
});

// ADR 0012: PNG sale del conjunto. No lo produce ningún cliente y cada formato admitido es un
// decodificador más que ejecutan los dispositivos de quien mire el perfil.
Deno.test("PNG ya no es un formato admitido", () => {
  assertEquals(formatFromMime("image/png"), null);
});

Deno.test("formatFromMime reconoce los dos admitidos", () => {
  assertEquals(formatFromMime("image/webp"), "webp");
  assertEquals(formatFromMime("image/jpeg"), "jpeg");
});

Deno.test("formatFromMime devuelve null ante cualquier otra cosa", () => {
  for (const mime of ["image/gif", "text/html", "application/zip", "", "webp", "image/*"]) {
    assertEquals(formatFromMime(mime), null, `deberia rechazar ${mime}`);
  }
});

Deno.test("extensionForFormat da la extension de cada formato", () => {
  assertEquals(extensionForFormat("webp"), ".webp");
  assertEquals(extensionForFormat("jpeg"), ".jpg");
});

Deno.test("formatMime da el content-type que se firma", () => {
  assertEquals(formatMime("webp"), "image/webp");
  assertEquals(formatMime("jpeg"), "image/jpeg");
});

// Ida y vuelta: lo que se firma tiene que volver a resolverse al mismo formato.
Deno.test("formatMime y formatFromMime son inversas", () => {
  for (const format of ["webp", "jpeg"] as const) {
    assertEquals(formatFromMime(formatMime(format)), format);
  }
});

Deno.test("formatFromPath resuelve la extension de una clave de R2", () => {
  const base = "avatars/da2de860-429c-4b9f-8458-feb74d6b5a6a/8f14e45f-ceea-4067-a0ba-8f14e45fceea";
  assertEquals(formatFromPath(`${base}.webp`), "webp");
  assertEquals(formatFromPath(`${base}.jpg`), "jpeg");
});

Deno.test("formatFromPath rechaza extensiones que no admitimos", () => {
  const base = "avatars/da2de860-429c-4b9f-8458-feb74d6b5a6a/foto";
  for (const ext of [".png", ".jpeg", ".gif", ".webp.exe", "", ".WEBP"]) {
    assertEquals(formatFromPath(`${base}${ext}`), null, `deberia rechazar '${ext}'`);
  }
});

// `.jpeg` como extensión NO se admite aunque el mime sea image/jpeg: la clave la acuña el
// servidor, así que solo existe una forma de escribirla. Aceptar dos sería aceptar que la misma
// foto tenga dos nombres posibles.
Deno.test("la extension canonica de jpeg es .jpg y solo .jpg", () => {
  assertEquals(extensionForFormat("jpeg"), ".jpg");
  assertEquals(formatFromPath("avatars/x/y.jpeg"), null);
});

Deno.test("MAX_DIMENSION son 2048", () => {
  assertEquals(MAX_DIMENSION, 2048);
});

// --- fixtures ---------------------------------------------------------------
//
// Los WebP se construyen a mano byte a byte, con los desplazamientos del contenedor RIFF. Es la
// única forma sin un codificador delante, y es también la debilidad conocida de estos tests: si el
// parser y el fixture comparten un malentendido, los dos pasan. Por eso el JPEG NO es sintético —
// se lee un fichero real del repositorio, cuyas dimensiones se comprobaron aparte con
// System.Drawing (259×535).

function riffWebp(chunk: Uint8Array): Uint8Array {
  const bytes = new Uint8Array(12 + chunk.length);
  bytes.set([0x52, 0x49, 0x46, 0x46], 0); // "RIFF"
  new DataView(bytes.buffer).setUint32(4, 4 + chunk.length, true); // tamaño
  bytes.set([0x57, 0x45, 0x42, 0x50], 8); // "WEBP"
  bytes.set(chunk, 12);
  return bytes;
}

/** WebP con pérdida ("VP8 "): las dimensiones van en 14 bits tras el start code 9D 01 2A. */
function webpLossy(width: number, height: number): Uint8Array {
  const chunk = new Uint8Array(8 + 10);
  chunk.set([0x56, 0x50, 0x38, 0x20], 0); // "VP8 "
  const view = new DataView(chunk.buffer);
  view.setUint32(4, 10, true);
  chunk.set([0x00, 0x00, 0x00], 8); // frame tag
  chunk.set([0x9d, 0x01, 0x2a], 11); // start code
  view.setUint16(14, width & 0x3fff, true);
  view.setUint16(16, height & 0x3fff, true);
  return riffWebp(chunk);
}

/** WebP sin pérdida ("VP8L"): 14 bits de ancho-1 y 14 de alto-1 empaquetados tras el 0x2F. */
function webpLossless(width: number, height: number): Uint8Array {
  const chunk = new Uint8Array(8 + 5);
  chunk.set([0x56, 0x50, 0x38, 0x4c], 0); // "VP8L"
  const view = new DataView(chunk.buffer);
  view.setUint32(4, 5, true);
  chunk[8] = 0x2f; // firma
  view.setUint32(9, ((width - 1) & 0x3fff) | (((height - 1) & 0x3fff) << 14), true);
  return riffWebp(chunk);
}

/** WebP extendido ("VP8X"): lienzo en dos enteros de 24 bits little-endian, menos uno. */
function webpExtended(width: number, height: number): Uint8Array {
  const chunk = new Uint8Array(8 + 10);
  chunk.set([0x56, 0x50, 0x38, 0x58], 0); // "VP8X"
  new DataView(chunk.buffer).setUint32(4, 10, true);
  chunk[8] = 0x10; // flags
  const w = width - 1;
  const h = height - 1;
  chunk.set([w & 0xff, (w >> 8) & 0xff, (w >> 16) & 0xff], 12);
  chunk.set([h & 0xff, (h >> 8) & 0xff, (h >> 16) & 0xff], 15);
  return riffWebp(chunk);
}

const REAL_JPEG = Deno.readFileSync(
  new URL("../../../../../pictures/screens/08-profile.jpeg", import.meta.url),
);

// --- sniffFormat ------------------------------------------------------------

Deno.test("sniffFormat: reconoce un webp real por RIFF/WEBP", () => {
  assertEquals(sniffFormat(webpLossy(512, 512)), "webp");
});

Deno.test("sniffFormat: reconoce un jpeg de verdad del repositorio", () => {
  assertEquals(sniffFormat(REAL_JPEG), "jpeg");
});

Deno.test("sniffFormat: un ZIP renombrado no es una imagen", () => {
  // "PK\x03\x04" — exactamente el caso que 0013 existe para cerrar.
  assertEquals(sniffFormat(new Uint8Array([0x50, 0x4b, 0x03, 0x04, 0, 0, 0, 0, 0, 0, 0, 0])), null);
});

Deno.test("sniffFormat: un PNG ya no cuenta como imagen admitida", () => {
  const png = new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0, 0, 0, 0]);
  assertEquals(sniffFormat(png), null);
});

Deno.test("sniffFormat: RIFF que no es WEBP (un WAV) no cuela", () => {
  const wav = new Uint8Array(12);
  wav.set([0x52, 0x49, 0x46, 0x46], 0);
  wav.set([0x57, 0x41, 0x56, 0x45], 8); // "WAVE"
  assertEquals(sniffFormat(wav), null);
});

Deno.test("sniffFormat: un fichero mas corto que la firma no revienta", () => {
  for (const n of [0, 1, 2, 3, 11]) {
    assertEquals(sniffFormat(new Uint8Array(n)), null, `longitud ${n}`);
  }
});

// --- readDimensions ---------------------------------------------------------

Deno.test("readDimensions: webp con perdida", () => {
  assertEquals(readDimensions(webpLossy(640, 480), "webp"), { width: 640, height: 480 });
});

Deno.test("readDimensions: webp sin perdida", () => {
  assertEquals(readDimensions(webpLossless(640, 480), "webp"), { width: 640, height: 480 });
});

Deno.test("readDimensions: webp extendido", () => {
  assertEquals(readDimensions(webpExtended(640, 480), "webp"), { width: 640, height: 480 });
});

// El fichero es real y sus dimensiones se midieron con una herramienta ajena a este código.
// Si el parser de JPEG está mal, este test lo dice; los sintéticos no podrían.
Deno.test("readDimensions: jpeg real del repositorio da 259x535", () => {
  assertEquals(readDimensions(REAL_JPEG, "jpeg"), { width: 259, height: 535 });
});

Deno.test("readDimensions: cabecera truncada devuelve null en vez de reventar", () => {
  assertEquals(readDimensions(webpLossy(640, 480).slice(0, 20), "webp"), null);
  assertEquals(readDimensions(REAL_JPEG.slice(0, 4), "jpeg"), null);
});

// --- assertValidImageBytes --------------------------------------------------

Deno.test("assertValidImageBytes: un webp correcto pasa", () => {
  assertValidImageBytes(webpLossy(512, 512), "webp");
});

Deno.test("assertValidImageBytes: un jpeg real pasa", () => {
  assertValidImageBytes(REAL_JPEG, "jpeg");
});

Deno.test("assertValidImageBytes: bytes que no son imagen son 400", () => {
  const zip = new Uint8Array([0x50, 0x4b, 0x03, 0x04, 0, 0, 0, 0, 0, 0, 0, 0]);
  assertEquals(assertThrows(() => assertValidImageBytes(zip, "webp"), AppError).status, 400);
});

// Subir un JPEG a una clave .webp: los bytes no mienten, la extensión sí.
Deno.test("assertValidImageBytes: formato que no coincide con lo declarado es 400", () => {
  assertEquals(
    assertThrows(() => assertValidImageBytes(REAL_JPEG, "webp"), AppError).status,
    400,
  );
});

// Bomba de descompresión: pesa nada y declara un lienzo enorme.
Deno.test("assertValidImageBytes: mas de 2048 de lado es 400", () => {
  assertEquals(
    assertThrows(() => assertValidImageBytes(webpExtended(16384, 16384), "webp"), AppError).status,
    400,
  );
});

Deno.test("assertValidImageBytes: exactamente 2048 pasa", () => {
  assertValidImageBytes(webpExtended(2048, 2048), "webp");
});

// Falla cerrado: si la cabecera no se puede leer, no se acepta.
Deno.test("assertValidImageBytes: cabecera ilegible es 400", () => {
  const truncado = webpLossy(512, 512).slice(0, 20);
  assertEquals(
    assertThrows(() => assertValidImageBytes(truncado, "webp"), AppError).status,
    400,
  );
});
