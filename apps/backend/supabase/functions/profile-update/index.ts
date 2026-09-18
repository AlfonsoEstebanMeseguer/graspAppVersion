// profile-update — HTTP (app)
//
// Actualiza los campos editables del perfil del usuario autenticado. Todos son opcionales, pero
// al menos uno debe venir en el body. `display_name` vive en `profiles` (público);
// `birth_date`/`gender`/`country` viven en `profiles_private` (sensibles, RLS solo-dueño). No
// requiere service_role: las policies "_update_own" de ambas tablas ya limitan la escritura a la
// fila propia; se usa el cliente con el JWT del usuario para que RLS siga siendo la barrera real.
//
// `gender` valida contra el enum documentado en docs/db-schema.md ("hombre" | "mujer" | "otro");
// la columna es `text` sin CHECK a nivel de Postgres, así que esta función es la única barrera
// contra valores arbitrarios — no confiar en que el cliente Flutter mande siempre uno válido.
import { handleCorsPreflight } from "../_shared/cors.ts";
import { AppError, errorResponse, jsonResponse } from "../_shared/http.ts";
import { requireAuthUser } from "../_shared/supabase-client.ts";
import { isNonEmptyString } from "../_shared/validation.ts";

const ALLOWED_GENDERS = ["hombre", "mujer", "otro"] as const;
const COUNTRY_REGEX = /^[\p{L} .'-]{2,56}$/u;
const DATE_REGEX = /^\d{4}-\d{2}-\d{2}$/;

interface ProfileUpdateBody {
  display_name?: string;
  birth_date?: string;
  gender?: string;
  country?: string;
}

function validateBirthDate(value: string): void {
  if (!DATE_REGEX.test(value)) {
    throw new AppError(400, "invalid_input", "birth_date debe tener formato YYYY-MM-DD", {
      field: "birth_date",
    });
  }
  const date = new Date(`${value}T00:00:00Z`);
  if (Number.isNaN(date.getTime())) {
    throw new AppError(400, "invalid_input", "birth_date no es una fecha válida", {
      field: "birth_date",
    });
  }
  const ageMs = Date.now() - date.getTime();
  const ageYears = ageMs / (1000 * 60 * 60 * 24 * 365.25);
  if (ageYears < 13 || ageYears > 120) {
    throw new AppError(400, "invalid_input", "birth_date implica una edad fuera de rango", {
      field: "birth_date",
    });
  }
}

function parseBody(raw: unknown): ProfileUpdateBody {
  if (typeof raw !== "object" || raw === null) {
    throw new AppError(400, "invalid_input", "El body debe ser un objeto JSON");
  }
  const body = raw as Record<string, unknown>;
  const result: ProfileUpdateBody = {};

  const providedFields = ["display_name", "birth_date", "gender", "country"]
    .filter((field) => body[field] !== undefined);

  if (providedFields.length === 0) {
    throw new AppError(400, "invalid_input", "Debe venir al menos un campo a actualizar");
  }

  if (body.display_name !== undefined) {
    if (!isNonEmptyString(body.display_name, 60)) {
      throw new AppError(400, "invalid_input", "display_name inválido (1-60 caracteres)", {
        field: "display_name",
      });
    }
    result.display_name = (body.display_name as string).trim();
  }

  if (body.birth_date !== undefined) {
    if (typeof body.birth_date !== "string") {
      throw new AppError(400, "invalid_input", "birth_date debe ser string", {
        field: "birth_date",
      });
    }
    validateBirthDate(body.birth_date);
    result.birth_date = body.birth_date;
  }

  if (body.gender !== undefined) {
    if (
      typeof body.gender !== "string" ||
      !(ALLOWED_GENDERS as readonly string[]).includes(body.gender)
    ) {
      throw new AppError(400, "invalid_input", `gender debe ser uno de: ${ALLOWED_GENDERS.join(", ")}`, {
        field: "gender",
      });
    }
    result.gender = body.gender;
  }

  if (body.country !== undefined) {
    if (typeof body.country !== "string" || !COUNTRY_REGEX.test(body.country.trim())) {
      throw new AppError(400, "invalid_input", "country inválido (2-56 caracteres alfabéticos)", {
        field: "country",
      });
    }
    result.country = body.country.trim();
  }

  return result;
}

Deno.serve(async (req: Request) => {
  const preflight = handleCorsPreflight(req);
  if (preflight) return preflight;

  try {
    if (req.method !== "PATCH") {
      throw new AppError(405, "method_not_allowed", "Usa PATCH");
    }

    const { userId, client } = await requireAuthUser(req);

    let rawBody: unknown;
    try {
      rawBody = await req.json();
    } catch {
      throw new AppError(400, "invalid_input", "Body no es JSON válido");
    }
    const body = parseBody(rawBody);

    const publicUpdate: Record<string, string> = {};
    if (body.display_name !== undefined) publicUpdate.display_name = body.display_name;

    const privateUpdate: Record<string, string> = {};
    if (body.birth_date !== undefined) privateUpdate.birth_date = body.birth_date;
    if (body.gender !== undefined) privateUpdate.gender = body.gender;
    if (body.country !== undefined) privateUpdate.country = body.country;

    if (Object.keys(publicUpdate).length > 0) {
      const { error } = await client
        .from("profiles")
        .update(publicUpdate)
        .eq("user_id", userId);
      if (error) {
        throw new AppError(500, "internal_error", "No se pudo actualizar profiles", {
          cause: error.message,
        });
      }
    }

    if (Object.keys(privateUpdate).length > 0) {
      const { error } = await client
        .from("profiles_private")
        .update(privateUpdate)
        .eq("user_id", userId);
      if (error) {
        throw new AppError(500, "internal_error", "No se pudo actualizar profiles_private", {
          cause: error.message,
        });
      }
    }

    const updatedFields = [...Object.keys(publicUpdate), ...Object.keys(privateUpdate)];

    return jsonResponse({ success: true, user_id: userId, updated_fields: updatedFields }, 200);
  } catch (err) {
    return errorResponse(err);
  }
});
