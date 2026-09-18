// account-delete — HTTP (app)
//
// Borra la cuenta del usuario autenticado. Es el **punto de entrada del derecho de supresión**
// (Art. 17 RGPD) y no existía: la auditoría del 2026-08-15 (H-SV-02) encontró que toda la cascada
// de borrado estaba construida y probada —trigger, `storage_gc_queue`, `media-gc-cron`,
// reconciliación, y la retirada de las FK lápida que costó el incidente de `20260810140000`— pero
// **no había forma de dispararla**: ni Edge Function, ni pantalla, ni nada. Solo alguien con acceso
// al panel de Supabase ejecutando SQL a mano. Eso no es un mecanismo de supresión, es un favor.
//
// Además bloqueaba la publicación: App Store (guideline 5.1.1(v), desde 2022) y Google Play exigen
// borrado de cuenta DENTRO de la app para cualquier app que permita crear una.
//
// ===== Qué borra, y quién lo borra de verdad =====
//
// Esta función NO borra tablas. Llama a `auth.admin.deleteUser`, y el borrado en cascada lo hace
// Postgres por las FK `on delete cascade` contra `auth.users`. Comprobado contra base real: se van
// `profiles`, `profiles_private`, `user_experiences`, `onboarding_responses`, `user_badges`, y el
// trigger encola `profiles.photo_path` en `storage_gc_queue` para que `media-gc-cron` borre el
// objeto de R2.
//
// Por eso NO hace falta conceder `DELETE` a `service_role` sobre ninguna tabla —la auditoría
// proponía hacerlo y se comprobó que sobra—: GoTrue borra la fila de `auth.users` como
// `supabase_auth_admin`, y las acciones de integridad referencial se ejecutan sin comprobar
// permisos del invocador. Un grant de más habría sido superficie regalada.
//
// ===== Lo que SOBREVIVE, y por qué =====
//
// `photo_audit_log` conserva 90 días (`20260812090000`) por el Art. 6.1.c: es el registro de que
// una imagen concreta se aprobó y se sirvió, y existe para responder ante una reclamación de
// contenido. No lleva FK contra `auth.users` — es una lápida (ver el invariante de `CLAUDE.md`) —
// así que sobrevive al borrado por diseño, no por descuido. La UI tiene que decirlo.
import { handleCorsPreflight } from "../_shared/cors.ts";
import { AppError, errorResponse, jsonResponse } from "../_shared/http.ts";
import { parseAccountDeleteRequest } from "../_shared/account-delete.ts";
import { getServiceRoleClient, requireAuthUser } from "../_shared/supabase-client.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

Deno.serve(async (req: Request) => {
  const preflight = handleCorsPreflight(req);
  if (preflight) return preflight;

  try {
    if (req.method !== "POST") {
      throw new AppError(405, "method_not_allowed", "Usa POST");
    }

    const { userId, email } = await requireAuthUser(req);

    let rawBody: unknown;
    try {
      rawBody = await req.json();
    } catch {
      throw new AppError(400, "invalid_input", "Body no es JSON válido");
    }

    const { password } = parseAccountDeleteRequest(rawBody);

    // ===== Reautenticación =====
    //
    // El JWT solo demuestra que hubo un login en algún momento de su vigencia. Para una acción
    // irreversible eso no basta: quien coge un móvil desbloqueado tiene un JWT válido. Se exige la
    // contraseña AHORA.
    //
    // Pesa más aquí que en otras apps porque la decisión 0005 dejó el alta **sin verificación de
    // correo**: no hay un segundo factor al que recurrir después. Si el borrado se pudiera hacer
    // solo con la sesión, la ventana entre robar el móvil y perder la cuenta sería cero.
    if (email === null) {
      // Fallar cerrado. Si algún día hay altas sin correo (teléfono, anónimas), este camino no
      // puede reautenticar y NO debe borrar por eso: debe negarse ruidosamente para que quien
      // añada ese tipo de alta tenga que resolver también cómo se confirma su borrado.
      throw new AppError(
        409,
        "reauth_unavailable",
        "Esta cuenta no tiene correo asociado; el borrado no puede confirmarse por esta vía",
      );
    }

    // Cliente ANÓNIMO y desechable, nunca `getUserClient(req)`: comprobar la contraseña con el
    // cliente que ya lleva la sesión del usuario mezclaría el estado de sesión de la petición con
    // el intento de login, y un fallo dejaría el cliente en un estado que nadie quiere razonar.
    const authProbe = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { auth: { persistSession: false, autoRefreshToken: false } },
    );

    const { data: signIn, error: signInError } = await authProbe.auth.signInWithPassword({
      email,
      password,
    });

    if (signInError || !signIn.user) {
      // Mensaje deliberadamente pobre: no se distingue "contraseña mal" de cualquier otro fallo de
      // auth, y no se devuelve el error interno de GoTrue. Quien llama ya sabe qué cuenta es.
      throw new AppError(401, "invalid_credentials", "La contraseña no es correcta");
    }

    // La contraseña correcta de OTRA cuenta no sirve para borrar esta. Sin esta comprobación, el
    // `email` sale del JWT y el `password` del body, así que coinciden siempre — pero si algún día
    // el correo llegara a venir del body, esto es lo que impide el salto lateral. Cuesta una
    // comparación y cierra una clase entera de fallo antes de que exista.
    if (signIn.user.id !== userId) {
      throw new AppError(401, "invalid_credentials", "La contraseña no es correcta");
    }

    // La sesión que acabamos de abrir para comprobar la contraseña se cierra: no debe quedar viva
    // más allá de la comprobación.
    await authProbe.auth.signOut();

    // ===== El borrado =====
    const service = getServiceRoleClient();
    const { error: deleteError } = await service.auth.admin.deleteUser(userId);

    if (deleteError) {
      // No se devuelve el mensaje de GoTrue al cliente: puede describir el estado interno de auth.
      console.error(`account-delete: fallo al borrar ${userId}:`, deleteError.message);
      throw new AppError(500, "internal_error", "No se pudo borrar la cuenta");
    }

    // Se registra el borrado sin el identificador de quien se borró, que sería precisamente el dato
    // que hay que suprimir. Basta para ver la tasa de bajas en los logs.
    console.info("account-delete: cuenta borrada");

    return jsonResponse({ success: true }, 200);
  } catch (err) {
    return errorResponse(err);
  }
});
