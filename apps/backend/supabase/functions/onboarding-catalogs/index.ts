// onboarding-catalogs — HTTP (app)
//
// Devuelve los catálogos de opciones del cuestionario de alta (categorías, casos concretos,
// perfiles de oyente, fuentes de descubrimiento) para que Flutter los pinte en tiempo de
// ejecución sin duplicar los slugs a mano en `onboarding_question.dart`. Es la contrapartida de
// lectura de `onboarding-complete`: los slugs que este endpoint expone son exactamente los que
// esa función acepta — nunca deben divergir (comparten `_shared/onboarding-catalogs.ts` para la
// parte hardcodeada, y las mismas tablas para `categories` / `experience_cases`).
//
// Requiere service_role: no estrictamente (categories/experience_cases tienen policy de lectura
// pública para `authenticated`), pero se usa igualmente porque este endpoint no debe depender de
// que el llamador tenga un JWT válido de usuario — se sirve antes de terminar el registro, y
// listar catálogos no expone nada sensible (a diferencia de `user_experiences`, que sí requiere
// auth). No hay operación de escritura.
//
// Contrato completo: docs/api-contracts.md § Bloque 2.
import { handleCorsPreflight } from "../_shared/cors.ts";
import { errorResponse, jsonResponse, AppError } from "../_shared/http.ts";
import { getServiceRoleClient } from "../_shared/supabase-client.ts";
import { DISCOVERY_SOURCES, LISTENER_PROFILES } from "../_shared/onboarding-catalogs.ts";

Deno.serve(async (req: Request) => {
  const preflight = handleCorsPreflight(req);
  if (preflight) return preflight;

  try {
    if (req.method !== "GET") {
      throw new AppError(405, "method_not_allowed", "Usa GET");
    }

    const service = getServiceRoleClient();

    const [categoriesResult, casesResult] = await Promise.all([
      // El `id` va además del `slug` porque hay un segundo consumidor: la fila de chips de la
      // pantalla de salas (ADR 0032), y `rooms-feed` filtra por uuid (`p_category uuid`), no por
      // slug. Es aditivo: el onboarding sigue mandando slugs a `onboarding-complete` y el mapper de
      // Flutter ignora las claves que no conoce. No expone nada — `categories` es un catálogo con
      // policy de lectura `using (true)`.
      service.from("categories").select("id, slug, name").order("name"),
      service
        .from("experience_cases")
        .select("slug, label, sort_order, categories(slug)")
        .order("sort_order"),
    ]);

    if (categoriesResult.error) {
      throw new AppError(500, "internal_error", "No se pudieron leer las categorías", {
        cause: categoriesResult.error.message,
      });
    }
    if (casesResult.error) {
      throw new AppError(500, "internal_error", "No se pudieron leer los casos concretos", {
        cause: casesResult.error.message,
      });
    }

    const experienceCases = (casesResult.data ?? []).map((row) => ({
      slug: row.slug as string,
      name: row.label as string,
      // `categories` viaja embebido vía la FK `experience_cases.category_id`; puede ser null
      // (categoría borrada con `on delete set null`), de ahí el fallback.
      category_slug: (row as { categories?: { slug: string } | null }).categories?.slug ?? null,
    }));

    return jsonResponse(
      {
        categories: categoriesResult.data ?? [],
        experience_cases: experienceCases,
        listener_profiles: LISTENER_PROFILES,
        discovery_sources: DISCOVERY_SOURCES,
      },
      200,
    );
  } catch (err) {
    return errorResponse(err);
  }
});