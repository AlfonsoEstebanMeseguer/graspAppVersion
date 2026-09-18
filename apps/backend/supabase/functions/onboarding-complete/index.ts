// onboarding-complete — HTTP (app)
//
// Responsabilidad (Sección 11 del documento maestro + docs/Grasp-Fase1.md § Bloque 2): valida las
// respuestas del cuestionario de alta, las guarda en `onboarding_responses` (auditoría/historial),
// resuelve `experiences` contra `experience_cases` para escribir `user_experiences`, y actualiza
// `profiles_private.primary_category_id` / `secondary_categories`.
//
// Contrato reescrito el 2026-08-09 (auditoría post-Bloque 2, ver
// `.claude/agent-memory/backend-agent/MEMORY.md`): el body pasa a ser un objeto **plano** con
// slugs en español — `{situation, experiences, profile, interests, discovery}` — en vez del
// `{"answers": {...}}` anidado con ids en inglés que enviaba el cliente. Este backend es la fuente
// de verdad del contrato; el cliente Flutter se adapta a él, no al revés.
//
// Requiere service_role: sí. `user_experiences` no tiene policy de escritura para el usuario a
// propósito (Art. 9 RGPD — ver la migración de Bloque 2): la escribe únicamente esta función, a
// partir de slugs ya validados contra `experience_cases`, nunca a partir de un id que mande el
// cliente. `onboarding_responses` y `profiles_private` sí tienen policies "_own", pero se escriben
// con el mismo cliente de servicio para no mezclar dos niveles de permiso en una misma operación
// lógica (todo o nada, aunque no haya transacción real entre tablas — ver nota de idempotencia).
//
// Contrato completo: docs/api-contracts.md § Bloque 2.
import { handleCorsPreflight } from "../_shared/cors.ts";
import { AppError, errorResponse, jsonResponse } from "../_shared/http.ts";
import { getServiceRoleClient, requireAuthUser } from "../_shared/supabase-client.ts";
import { DISCOVERY_SOURCES, isKnownSlug, LISTENER_PROFILES } from "../_shared/onboarding-catalogs.ts";
import { isNonEmptyString, isStringArray, requireField, toSlug } from "../_shared/validation.ts";

interface OnboardingBody {
  situation: string;
  experiences: string[];
  profile: string;
  interests: string[];
  discovery: string;
}

function parseBody(raw: unknown): OnboardingBody {
  if (typeof raw !== "object" || raw === null) {
    throw new AppError(400, "invalid_input", "El body debe ser un objeto JSON");
  }
  const body = raw as Record<string, unknown>;

  requireField(isNonEmptyString(body.situation, 100), "situation", "requerido: string no vacío (slug de categories)");

  requireField(
    isStringArray(body.experiences, { minLength: 1, maxLength: 20, itemMaxLength: 100 }),
    "experiences",
    "requerido: array de 1 a 20 strings (slugs de experience_cases)",
  );

  requireField(isNonEmptyString(body.profile, 100), "profile", "requerido: string no vacío (slug de listener profile)");

  requireField(
    isStringArray(body.interests, { minLength: 1, maxLength: 12, itemMaxLength: 100 }),
    "interests",
    "requerido: array de 1 a 12 strings",
  );

  requireField(isNonEmptyString(body.discovery, 100), "discovery", "requerido: string no vacío (slug de discovery source)");

  return {
    situation: body.situation as string,
    experiences: body.experiences as string[],
    profile: body.profile as string,
    interests: body.interests as string[],
    discovery: body.discovery as string,
  };
}

Deno.serve(async (req: Request) => {
  const preflight = handleCorsPreflight(req);
  if (preflight) return preflight;

  try {
    if (req.method !== "POST") {
      throw new AppError(405, "method_not_allowed", "Usa POST");
    }

    // La autenticación se resuelve siempre del JWT verificado, nunca de un `user_id` del body.
    const { userId } = await requireAuthUser(req);

    let rawBody: unknown;
    try {
      rawBody = await req.json();
    } catch {
      throw new AppError(400, "invalid_input", "Body no es JSON válido");
    }
    const body = parseBody(rawBody);

    const situationSlug = toSlug(body.situation);
    const experienceSlugs = [...new Set(body.experiences.map((s) => toSlug(s)))];
    const profileSlug = toSlug(body.profile);
    const discoverySlug = toSlug(body.discovery);

    if (!isKnownSlug(LISTENER_PROFILES, profileSlug)) {
      throw new AppError(422, "unknown_category", "`profile` no corresponde a ningún perfil de oyente conocido", {
        field: "profile",
        unknownSlugs: [profileSlug],
      });
    }

    if (!isKnownSlug(DISCOVERY_SOURCES, discoverySlug)) {
      throw new AppError(422, "unknown_category", "`discovery` no corresponde a ninguna fuente conocida", {
        field: "discovery",
        unknownSlugs: [discoverySlug],
      });
    }

    const service = getServiceRoleClient();

    const { data: category, error: categoryError } = await service
      .from("categories")
      .select("id, slug")
      .eq("slug", situationSlug)
      .maybeSingle();

    if (categoryError) {
      throw new AppError(500, "internal_error", "No se pudo resolver la categoría", {
        cause: categoryError.message,
      });
    }
    if (!category) {
      throw new AppError(422, "unknown_category", "`situation` no corresponde a ninguna categoría existente", {
        field: "situation",
        unknownSlugs: [situationSlug],
      });
    }
    const primaryCategoryId = category.id as string;

    const { data: matchedCases, error: casesError } = await service
      .from("experience_cases")
      .select("id, slug, category_id")
      .in("slug", experienceSlugs);

    if (casesError) {
      throw new AppError(500, "internal_error", "No se pudieron resolver las experiencias", {
        cause: casesError.message,
      });
    }

    const slugToCase = new Map((matchedCases ?? []).map((c) => [c.slug as string, c]));
    const unknownExperienceSlugs = experienceSlugs.filter((slug) => !slugToCase.has(slug));
    if (unknownExperienceSlugs.length > 0) {
      throw new AppError(422, "unknown_category", "`experiences` contiene slugs desconocidos", {
        field: "experiences",
        unknownSlugs: unknownExperienceSlugs,
      });
    }

    const experienceCaseIds = experienceSlugs.map((slug) => slugToCase.get(slug)!.id as string);

    // `secondary_categories` se deriva de las categorías a las que apuntan las experiencias
    // concretas elegidas, no de una lista de situaciones aparte: es el `category_id` de cada
    // `experience_case` (deduplicado, sin la primaria) — así el algoritmo de afinidad recibe una
    // sola fuente de verdad para "de qué categorías habla este usuario".
    const secondaryCategoryIds = [
      ...new Set(
        (matchedCases ?? [])
          .map((c) => c.category_id as string | null)
          .filter((id): id is string => Boolean(id) && id !== primaryCategoryId),
      ),
    ];

    const responses = {
      situation: situationSlug,
      experiences: experienceSlugs,
      profile: profileSlug,
      interests: body.interests,
      discovery: discoverySlug,
    };

    const { error: upsertError } = await service
      .from("onboarding_responses")
      .upsert({ user_id: userId, responses }, { onConflict: "user_id" });

    if (upsertError) {
      throw new AppError(500, "internal_error", "No se pudo guardar el onboarding", {
        cause: upsertError.message,
      });
    }

    // `user_experiences` se sincroniza con el conjunto enviado: se borra lo que ya no está
    // seleccionado y se inserta lo nuevo, sin duplicar (PK compuesta `(user_id,
    // experience_case_id)`). Reenviar el mismo body dos veces converge al mismo estado final.
    const { error: deleteError } = await service
      .from("user_experiences")
      .delete()
      .eq("user_id", userId)
      .not("experience_case_id", "in", `(${experienceCaseIds.join(",")})`);

    if (deleteError) {
      throw new AppError(500, "internal_error", "No se pudieron sincronizar las experiencias", {
        cause: deleteError.message,
      });
    }

    const { error: insertError } = await service
      .from("user_experiences")
      .upsert(
        experienceCaseIds.map((experience_case_id) => ({ user_id: userId, experience_case_id })),
        { onConflict: "user_id,experience_case_id", ignoreDuplicates: true },
      );

    if (insertError) {
      throw new AppError(500, "internal_error", "No se pudieron guardar las experiencias", {
        cause: insertError.message,
      });
    }

    const { error: profileUpdateError } = await service
      .from("profiles_private")
      .update({
        primary_category_id: primaryCategoryId,
        secondary_categories: secondaryCategoryIds,
      })
      .eq("user_id", userId);

    if (profileUpdateError) {
      throw new AppError(500, "internal_error", "No se pudo actualizar el perfil privado", {
        cause: profileUpdateError.message,
      });
    }

    return jsonResponse({ success: true, message: "onboarding saved", user_id: userId }, 200);
  } catch (err) {
    return errorResponse(err);
  }
});