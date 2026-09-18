// onboarding-get — HTTP (app)
//
// Devuelve las respuestas de onboarding del usuario autenticado. No está en la Sección 11 del
// documento maestro (se añadió para que la edición del feed desde Perfil, Bloque 3, pueda
// precargar el formulario sin re-registrarse — docs/Grasp-Fase1.md § Bloque 2). Solo lectura de
// la fila propia: RLS (`onboarding_responses_select_own`) ya impide leer la de otro usuario, pero
// además se filtra explícitamente por `user_id` para no depender solo de la policy.
import { handleCorsPreflight } from "../_shared/cors.ts";
import { AppError, errorResponse, jsonResponse } from "../_shared/http.ts";
import { requireAuthUser } from "../_shared/supabase-client.ts";

Deno.serve(async (req: Request) => {
  const preflight = handleCorsPreflight(req);
  if (preflight) return preflight;

  try {
    if (req.method !== "GET") {
      throw new AppError(405, "method_not_allowed", "Usa GET");
    }

    const { userId, client } = await requireAuthUser(req);

    const { data, error } = await client
      .from("onboarding_responses")
      .select("user_id, responses, updated_at")
      .eq("user_id", userId)
      .maybeSingle();

    if (error) {
      throw new AppError(500, "internal_error", "No se pudo leer el onboarding", {
        cause: error.message,
      });
    }

    if (!data) {
      throw new AppError(404, "onboarding_not_found", "El usuario todavía no completó el onboarding");
    }

    return jsonResponse(data, 200);
  } catch (err) {
    return errorResponse(err);
  }
});
