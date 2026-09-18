// profile-tag-rotate — HTTP (app)
//
// Rota el tag público del usuario (§6.2), con un tope de 1 cada 24 h.
//
// SOBRE LA CONTRADICCIÓN DE LA SPEC: el §1 dice que el tag es «inmutable» y el §6.2 que se puede
// «solicitar un nuevo tag». No se contradicen una vez se lee bien: **inmutable significa que el
// usuario no lo ELIGE**, no que no se pueda cambiar. Esta función cambia el tag; lo que nadie puede
// hacer es decidir cuál.
//
// Y esa garantía NO vive aquí. Vive en que `authenticated` no tiene `grant update` sobre
// `profiles.tag` y no lo tendrá nunca (migración 20260823120000, y el caso 6 de
// `tests/signup-validation.sql` lo fija). Por eso esta función usa `service_role`: es el único
// camino por el que la columna se puede escribir, y el valor lo acuña `public.mint_user_tag` dentro
// de la base de datos. Si la comprobación estuviera solo en este fichero, bastaría un `PATCH`
// directo a PostgREST para elegirse el tag.
import { handleCorsPreflight } from "../_shared/cors.ts";
import { AppError, errorResponse, jsonResponse } from "../_shared/http.ts";
import { getServiceRoleClient, requireAuthUser } from "../_shared/supabase-client.ts";
import { evaluateTagRotation, TAG_ROTATION_COOLDOWN_MS } from "../_shared/tag-rotate.ts";
import { isValidTag } from "../_shared/tag.ts";

interface TagRotateResponse {
  success: boolean;
  tag: string;
  /** Cuándo se podrá volver a rotar. El cliente lo usa para desactivar el botón. */
  next_rotation_at: string;
}

Deno.serve(async (req: Request) => {
  const preflight = handleCorsPreflight(req);
  if (preflight) return preflight;

  try {
    if (req.method !== "POST") {
      throw new AppError(405, "method_not_allowed", "Usa POST");
    }

    const { userId } = await requireAuthUser(req);
    const service = getServiceRoleClient();

    // Paso 1: el nombre visible (entrada de `mint_user_tag`) y la última rotación.
    const [{ data: profile, error: profileError }, { data: privateRow, error: privateError }] =
      await Promise.all([
        service.from("profiles").select("display_name").eq("user_id", userId).single(),
        service.from("profiles_private").select("tag_rotated_at").eq("user_id", userId).single(),
      ]);

    if (profileError || privateError) {
      throw new AppError(500, "internal_error", "No se pudo consultar el perfil", {
        cause: profileError?.message ?? privateError?.message,
      });
    }

    // Paso 2: el tope, con el mensaje que exige RN-21 — el límite concreto y CUÁNDO se recupera,
    // nunca un fallo mudo ni un genérico.
    const now = new Date();
    const decision = evaluateTagRotation(privateRow?.tag_rotated_at, now);
    if (!decision.allowed) {
      throw new AppError(
        422,
        "rate_limited",
        "Solo puedes cambiar tu tag una vez cada 24 horas",
        {
          limit: 1,
          window_hours: TAG_ROTATION_COOLDOWN_MS / 3_600_000,
          retry_at: decision.retryAt!.toISOString(),
        },
      );
    }

    // Paso 3: CONSUMIR EL CUPO ANTES DE ROTAR, y con la condición dentro del propio `update`.
    //
    // El orden importa y la condición también. Son dos escrituras en dos tablas sin transacción
    // que las una, así que hay que elegir qué se rompe si falla la segunda:
    //   · rotar primero y marcar después → si falla el marcado, el tope NO EXISTE: se puede rotar
    //     en bucle, invalidando cada vez el tag que los contactos habían guardado.
    //   · marcar primero y rotar después → si falla la rotación, se gasta un cupo sin cambiar nada.
    //     Molesto y raro; se espera 24 h. Falla cerrado, que es la dirección correcta.
    //
    // Y el `lte` hace de cerrojo: dos peticiones simultáneas evalúan el paso 2 a la vez y las dos
    // lo pasan, pero solo una de ellas encuentra fila que actualizar aquí. Sin esto, el tope se
    // salta con dos pulsaciones rápidas.
    const cutoff = new Date(now.getTime() - TAG_ROTATION_COOLDOWN_MS).toISOString();
    const { data: claimed, error: claimError } = await service
      .from("profiles_private")
      .update({ tag_rotated_at: now.toISOString() })
      .eq("user_id", userId)
      .or(`tag_rotated_at.is.null,tag_rotated_at.lte.${cutoff}`)
      .select("user_id");

    if (claimError) {
      throw new AppError(500, "internal_error", "No se pudo registrar la rotación", {
        cause: claimError.message,
      });
    }

    if (!claimed || claimed.length === 0) {
      // Otra petición del mismo usuario se llevó el cupo entre el paso 2 y el 3.
      throw new AppError(422, "rate_limited", "Solo puedes cambiar tu tag una vez cada 24 horas", {
        limit: 1,
        window_hours: TAG_ROTATION_COOLDOWN_MS / 3_600_000,
        retry_at: new Date(now.getTime() + TAG_ROTATION_COOLDOWN_MS).toISOString(),
      });
    }

    // Paso 4: acuñar. Lo hace la base de datos, que es la autoridad del formato y la que reintenta
    // contra el índice único. Aquí no se construye ningún tag.
    const { data: newTag, error: mintError } = await service.rpc("mint_user_tag", {
      p_display_name: profile.display_name,
    });

    if (mintError || typeof newTag !== "string") {
      throw new AppError(500, "internal_error", "No se pudo acuñar el tag", {
        cause: mintError?.message,
      });
    }

    // Cinturón: si el SQL y el espejo de Deno divergieran, se ve aquí y no en la pantalla del
    // usuario. La autoridad sigue siendo la migración — esto solo evita escribir algo con una forma
    // que el resto del sistema no sabe leer.
    if (!isValidTag(newTag)) {
      throw new AppError(500, "internal_error", "El tag acuñado no tiene el formato esperado");
    }

    const { error: writeError } = await service
      .from("profiles")
      .update({ tag: newTag })
      .eq("user_id", userId);

    if (writeError) {
      // El cupo ya está gastado (paso 3). Es la mitad "molesta" del compromiso de arriba, y se
      // registra para poder verlo en logs si pasara más de lo previsto.
      console.error("tag_rotate_write_failed", { userId, cause: writeError.message });
      throw new AppError(500, "internal_error", "No se pudo escribir el tag", {
        cause: writeError.message,
      });
    }

    const response: TagRotateResponse = {
      success: true,
      tag: newTag,
      next_rotation_at: new Date(now.getTime() + TAG_ROTATION_COOLDOWN_MS).toISOString(),
    };
    return jsonResponse(response, 200);
  } catch (err) {
    return errorResponse(err);
  }
});
