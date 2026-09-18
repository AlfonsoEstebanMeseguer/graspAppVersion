// connect-dismiss — HTTP (app)
//
// «No mostrar más» en Conectar (§6.4, decisión 8 del plan; RN-47(6), RN-48).
//
// POR QUÉ EXISTE ESTA FUNCIÓN, Y POR QUÉ LLEGA TARDE
// La decisión 8 del plan añadió el `✕` a la tarjeta porque «§2.7 y RN-47(6)/RN-48 exigen registrar a
// los rechazados y **ninguna pantalla lo escribía**». Se añadió la pantalla… y nadie se dio cuenta
// de que tampoco había **endpoint**: `connect_dismissals` solo tenía grants para `service_role`, sin
// policy de escritura, y `connect-feed` únicamente la LEÍA. El comentario de la tabla llegó a decir
// «la puerta de entrada es la acción discreta de la tarjeta», que era una promesa sin cumplir.
//
// Es exactamente el principio de CLAUDE.md —«un mecanismo sin puerta de entrada no existe»— cayendo
// dentro de la corrección escrita para evitarlo. La pregunta al auditar una capacidad no es solo
// «¿quién la dispara?» sino también **«¿y contra qué?»**.
//
// Corre con `service_role` porque `connect_dismissals` no concede nada a `authenticated`, igual que
// el resto de las tablas de `connect_*`. Se mantuvo así a propósito en vez de abrir un `grant
// insert`: hoy NINGUNA tabla de Conectar acepta escritura del cliente, y esa uniformidad es lo que
// hace corta la auditoría por roles.
import { handleCorsPreflight } from "../_shared/cors.ts";
import { AppError, errorResponse, jsonResponse } from "../_shared/http.ts";
import { getServiceRoleClient, requireAuthUser } from "../_shared/supabase-client.ts";
import { validateDismissal } from "../_shared/connect-dismiss.ts";

Deno.serve(async (req: Request) => {
  const preflight = handleCorsPreflight(req);
  if (preflight) return preflight;

  try {
    if (req.method !== "POST") {
      throw new AppError(405, "method_not_allowed", "Usa POST");
    }

    const { userId: actorId } = await requireAuthUser(req);

    let raw: unknown;
    try {
      raw = await req.json();
    } catch {
      throw new AppError(400, "invalid_input", "Body no es JSON válido");
    }

    const body = (raw ?? {}) as { dismissed_user_id?: unknown };

    // El `user_id` sale del JWT y NUNCA del body: si viniera de fuera, cualquiera podría llenar de
    // descartes la lista de otra persona y dejarle el feed de Conectar vacío.
    const verdict = validateDismissal({ actorId, target: body.dismissed_user_id });
    if (!verdict.ok) {
      throw new AppError(
        400,
        "invalid_input",
        verdict.reason === "self_dismiss"
          ? "No puedes descartarte a ti mismo"
          : "dismissed_user_id debe ser un uuid",
        { field: "dismissed_user_id" },
      );
    }

    const service = getServiceRoleClient();

    // Que exista se comprueba ANTES de insertar. La clave ajena lo impediría igual, pero saldría
    // como 23503 → 500; aquí es un 404 que dice la verdad.
    const { data: target, error: targetError } = await service
      .from("profiles")
      .select("user_id")
      .eq("user_id", verdict.row.dismissed_user_id)
      .maybeSingle();

    if (targetError) {
      throw new AppError(500, "internal_error", "No se pudo comprobar el usuario", {
        cause: targetError.message,
      });
    }
    if (!target) {
      throw new AppError(404, "not_found", "El usuario no existe");
    }

    // IDEMPOTENTE POR FORMA, no por clave: la primaria es el par `(user_id, dismissed_user_id)`, así
    // que descartar dos veces a la misma persona es un no-op. `ignoreDuplicates` evita que el
    // segundo intento suba como 23505 → 500 por algo que ya está como el cliente quería.
    //
    // Y RN-48 dice que los rechazos NO CADUCAN NUNCA, de ahí que la tabla no tenga columna de fecha
    // y que aquí no haya nada que actualizar: la fila o está o no está.
    const { error: insertError } = await service
      .from("connect_dismissals")
      .upsert(verdict.row, { onConflict: "user_id,dismissed_user_id", ignoreDuplicates: true });

    if (insertError) {
      throw new AppError(500, "internal_error", "No se pudo registrar el descarte", {
        cause: insertError.message,
      });
    }

    // 200 tanto si se escribió como si ya estaba, con el mismo cuerpo: el cliente quería que esa
    // persona dejara de aparecer, y deja de aparecer. El estado previo no es información que
    // necesite.
    return jsonResponse({ success: true, dismissed: true }, 200);
  } catch (err) {
    return errorResponse(err);
  }
});
