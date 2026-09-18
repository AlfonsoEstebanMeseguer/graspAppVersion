// Lógica pura de `account-delete`: validación del body.
// PURA: sin red, sin Supabase, sin credenciales — igual que `photo-upload.ts` y `photo-view.ts`.
import { AppError } from "./http.ts";

/**
 * Frase que hay que escribir para confirmar. Va en el contrato, no solo en la UI.
 *
 * Es la segunda barrera y protege de algo distinto que la contraseña: la contraseña demuestra
 * QUIÉN eres, la frase demuestra QUE SABES lo que vas a hacer. Un botón mal pulsado con la sesión
 * abierta pasa la primera y no la segunda.
 *
 * Se comprueba en el backend a propósito. Si viviera solo en el cliente, un `curl` con el JWT y la
 * contraseña —que es exactamente lo que tiene alguien que te coge el móvil desbloqueado— se la
 * salta. `CLAUDE.md`: las reglas críticas se validan server-side, nunca solo en el cliente.
 */
export const CONFIRMATION_PHRASE = "BORRAR MI CUENTA";

export interface AccountDeleteRequest {
  password: string;
  confirmation: string;
}

export function parseAccountDeleteRequest(raw: unknown): AccountDeleteRequest {
  if (typeof raw !== "object" || raw === null || Array.isArray(raw)) {
    throw new AppError(400, "invalid_input", "El body debe ser un objeto JSON");
  }
  const body = raw as Record<string, unknown>;

  if (typeof body.password !== "string" || body.password.length === 0) {
    throw new AppError(400, "invalid_input", "password requerido", { field: "password" });
  }

  if (typeof body.confirmation !== "string") {
    throw new AppError(400, "invalid_input", "confirmation requerido", { field: "confirmation" });
  }

  // Se normalizan espacios y mayúsculas: el usuario está escribiendo una frase a mano, muchas veces
  // en un móvil con autocorrector, y fallar por un espacio final sería crueldad sin ganancia de
  // seguridad. Lo que la frase demuestra es intención, y la intención sobrevive a un espacio.
  if (body.confirmation.trim().toUpperCase() !== CONFIRMATION_PHRASE) {
    throw new AppError(
      400,
      "invalid_input",
      `Para confirmar hay que escribir exactamente "${CONFIRMATION_PHRASE}"`,
      { field: "confirmation" },
    );
  }

  return { password: body.password, confirmation: CONFIRMATION_PHRASE };
}
