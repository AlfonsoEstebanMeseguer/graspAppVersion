// Lógica pura de `profile-avatar-set`: validación del body y comprobación de propiedad de la
// clave. PURA: sin red, sin Postgres, sin R2.
//
// Un usuario tiene UN avatar, y es una de dos cosas excluyentes:
//   · una foto suya subida a R2, de la que en `profiles.photo_path` va solo la clave del objeto;
//   · uno de los 8 avatares predeterminados, que son ASSETS LOCALES de Flutter y no existen en R2.
//
// Diseño: la exclusividad la impone la base de datos (`profiles_avatar_exclusive`), no este
// módulo. Aquí solo se rechaza pronto y con un mensaje legible lo que allí sería un 500 por
// violación de constraint.
import { AppError } from "./http.ts";
import { formatFromPath } from "./image-format.ts";
import { isNonEmptyString } from "./validation.ts";

/**
 * Los 8 avatares predeterminados.
 *
 * **La autoridad de esta lista es el `check` `profiles_preset_avatar_valid`**
 * (`20260813090000_add_preset_avatar_to_profiles.sql`), no este fichero. Existe aquí duplicada
 * para devolver un 400 legible en vez de un 500, y en `AvatarType` del cliente Flutter para
 * resolver el asset. Si divergen, gana el `check`: añadir un avatar exige tocar los tres sitios, y
 * ese coste es deliberado — es lo que impide que la columna degenere en texto libre.
 */
export const PRESET_AVATARS = [
  "gym",
  "reader",
  "music",
  "coding",
  "animal",
  "normal_1",
  "normal_2",
  "normal_3",
] as const;

export type PresetAvatar = typeof PRESET_AVATARS[number];

export type AvatarRequest =
  | { kind: "photo"; photoPath: string }
  | { kind: "preset"; preset: PresetAvatar };

function isPreset(value: unknown): value is PresetAvatar {
  return typeof value === "string" && (PRESET_AVATARS as readonly string[]).includes(value);
}

/**
 * Valida el body y devuelve cuál de los dos avatares se está fijando.
 *
 * Exige **exactamente uno** de `photo_path` o `preset`. Mandar los dos no es "elige tú": es una
 * petición ambigua sobre un recurso donde la ambigüedad significa borrar la foto de alguien o no
 * borrarla. Se rechaza.
 */
export function parseAvatarRequest(raw: unknown): AvatarRequest {
  if (typeof raw !== "object" || raw === null || Array.isArray(raw)) {
    throw new AppError(400, "invalid_input", "El body debe ser un objeto JSON");
  }
  const body = raw as Record<string, unknown>;

  const hasPhoto = body.photo_path !== undefined;
  const hasPreset = body.preset !== undefined;

  if (hasPhoto === hasPreset) {
    throw new AppError(
      400,
      "invalid_input",
      "Manda exactamente uno: photo_path (foto subida) o preset (avatar predeterminado)",
    );
  }

  if (hasPhoto) {
    if (!isNonEmptyString(body.photo_path, 256)) {
      throw new AppError(400, "invalid_input", "photo_path inválido (1-256 caracteres)", {
        field: "photo_path",
      });
    }
    const photoPath = body.photo_path as string;
    // La extensión se consulta en la tabla de formatos, no se compara contra un literal: así no
    // puede divergir de la que acuña `profile-photo-upload-url`. Una clave que esta función
    // rechazase dejaría la foto subida y sin confirmar, o sea huérfana en R2.
    if (formatFromPath(photoPath) === null) {
      throw new AppError(400, "invalid_input", "photo_path debe terminar en .webp o .jpg", {
        field: "photo_path",
      });
    }
    return { kind: "photo", photoPath };
  }

  if (!isPreset(body.preset)) {
    throw new AppError(
      400,
      "invalid_input",
      `preset debe ser uno de: ${PRESET_AVATARS.join(", ")}`,
      { field: "preset" },
    );
  }
  return { kind: "preset", preset: body.preset };
}

/**
 * Comprueba que la clave pertenece a quien la reclama.
 *
 * Sin esto, cualquiera podría apuntar su perfil a la clave de otro — y esa clave es lo único que
 * `profile-photo-view-url` acepta firmar, así que la comprobación de allí se apoya en esta de
 * aquí. La barra final del prefijo no es cosmética: sin ella, `avatars/<user>malicioso/` pasaría
 * por ser del usuario.
 */
export function assertPathOwnership(photoPath: string, userId: string): void {
  const expectedPrefix = `avatars/${userId}/`;
  if (!photoPath.startsWith(expectedPrefix)) {
    throw new AppError(403, "forbidden", "photo_path no pertenece a este usuario", {
      expected_prefix: expectedPrefix,
    });
  }
}
