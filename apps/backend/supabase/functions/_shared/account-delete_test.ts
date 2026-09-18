import { assertEquals, assertThrows } from "https://deno.land/std@0.208.0/assert/mod.ts";
import { AppError } from "./http.ts";
import { CONFIRMATION_PHRASE, parseAccountDeleteRequest } from "./account-delete.ts";

const VALID = { password: "unaClaveLarga123", confirmation: CONFIRMATION_PHRASE };

Deno.test("parseAccountDeleteRequest: acepta un body válido", () => {
  assertEquals(parseAccountDeleteRequest(VALID), {
    password: "unaClaveLarga123",
    confirmation: CONFIRMATION_PHRASE,
  });
});

Deno.test("parseAccountDeleteRequest: el body debe ser un objeto", () => {
  for (const bad of [null, "texto", 42, [VALID]]) {
    assertThrows(() => parseAccountDeleteRequest(bad), AppError);
  }
});

// La contraseña es la reautenticación. Sin ella, un JWT robado —el de un móvil desbloqueado— basta
// para borrar la cuenta, y la decisión 0005 dejó el proyecto sin verificación de correo, así que no
// hay segundo factor al que recurrir después.
Deno.test("parseAccountDeleteRequest: sin password no se puede confirmar", () => {
  assertThrows(() => parseAccountDeleteRequest({ confirmation: CONFIRMATION_PHRASE }), AppError);
});

Deno.test("parseAccountDeleteRequest: password vacía no cuenta como password", () => {
  assertThrows(
    () => parseAccountDeleteRequest({ password: "", confirmation: CONFIRMATION_PHRASE }),
    AppError,
  );
});

// La frase se comprueba en el BACKEND, no solo en la UI. Si viviera solo en el cliente, un `curl`
// con el JWT y la contraseña se la saltaría — y eso es exactamente lo que tiene quien te coge el
// móvil desbloqueado. `CLAUDE.md`: las reglas críticas nunca se validan solo en el cliente.
Deno.test("parseAccountDeleteRequest: sin la frase exacta no se borra", () => {
  for (const bad of ["", "borrar", "BORRAR MI CUENTA YA", "SÍ", "DELETE MY ACCOUNT"]) {
    assertThrows(
      () => parseAccountDeleteRequest({ password: "x", confirmation: bad }),
      AppError,
      undefined,
      `deberia rechazar "${bad}"`,
    );
  }
});

// Escribir a mano en un móvil con autocorrector no debe costar la operación: lo que la frase
// demuestra es INTENCIÓN, y la intención sobrevive a un espacio o a una minúscula.
Deno.test("parseAccountDeleteRequest: tolera espacios y minúsculas en la frase", () => {
  for (const ok of ["  BORRAR MI CUENTA  ", "borrar mi cuenta", "Borrar Mi Cuenta"]) {
    assertEquals(
      parseAccountDeleteRequest({ password: "x", confirmation: ok }).confirmation,
      CONFIRMATION_PHRASE,
    );
  }
});

Deno.test("parseAccountDeleteRequest: confirmation no string se rechaza", () => {
  assertThrows(() => parseAccountDeleteRequest({ password: "x", confirmation: 1 }), AppError);
});
