// connect-tag-lookup — HTTP (app)
//
// Búsqueda por tag exacto (§6.2). **Sin búsqueda difusa, y es permanente** (§13): el tag es la
// única forma de encontrar a alguien a propósito, porque una búsqueda por nombre convertiría una
// app de apoyo en un directorio de personas vulnerables.
//
// LOS CUATRO DESENLACES viven en `_shared/connect-lookup.ts`, que es puro y tiene los tests. Aquí
// solo se consulta y se traduce a HTTP. El motivo de esa separación es RN-23: la regla «un tag con
// bloqueo responde igual que si no existiera» es una comparación entre DOS respuestas, y eso no se
// puede probar mirando una rama de un `if`.
//
// LO QUE NO SE PROMETE, y queda escrito para que nadie lo dé por hecho: las dos respuestas son
// idénticas en CUERPO y en CÓDIGO, no en TIEMPO. Un bloqueo hace una consulta más que un tag
// inexistente, así que un atacante con muchas medidas podría distinguirlos por latencia.
//
// Eso NO es deuda pendiente: el ADR 0028 (2026-08-30) decide **no cerrarlo**. El tiempo constante
// artificial encarece el backend entero y no compra nada mientras siga abierto el oráculo ACTIVO
// —intentar escribir y ver que falla—, que es una sola petición y no falla nunca. `RN-23` protege el
// contenido de las respuestas, no la capacidad de actuar.
//
// La mitigación que sí sale de ese ADR **está aquí abajo**: un tope de `MAX_TAG_LOOKUPS_PER_DAY`
// búsquedas al día. No cierra el canal, lo acota por volumen —que es lo que un ataque de latencia
// necesita— y de paso frena la enumeración de tags por fuerza bruta, que era el problema peor.
//
// Requiere service_role: sí. Necesita resolver el tag contra CUALQUIER perfil y leer `blocks`, que
// solo lo lee su `blocker_id` (RN-23): con el cliente del usuario, la mitad «me bloquearon a mí»
// sería invisible y el bloqueo no taparía nada.
import { handleCorsPreflight } from "../_shared/cors.ts";
import { AppError, errorResponse, jsonResponse } from "../_shared/http.ts";
import { getServiceRoleClient, requireAuthUser } from "../_shared/supabase-client.ts";
import { isValidTag } from "../_shared/tag.ts";
import { resolveTagLookup } from "../_shared/connect-lookup.ts";
import { evaluateTagLookupLimit } from "../_shared/tag-lookup-limit.ts";

interface LookupBody {
  tag?: unknown;
}

/**
 * La respuesta de «no existe». UNA SOLA CONSTANTE, no dos literales iguales.
 *
 * Es la misma razón que el ADR 0022 da para el texto del input inerte: dos literales que hoy
 * coinciden divergen el día que alguien edita uno. Aquí la divergencia sería una fuga — el
 * bloqueado sabría que la cuenta existe.
 */
function notFound(): never {
  throw new AppError(404, "not_found", "No hay ninguna cuenta con ese tag");
}

Deno.serve(async (req: Request) => {
  const preflight = handleCorsPreflight(req);
  if (preflight) return preflight;

  try {
    // POST y no GET con `?tag=`: el tag lleva `#` dentro (`alfon#K7M2QX9F`), que en una URL es el
    // delimitador de fragmento. Un cliente que se olvide de codificarlo mandaría solo `alfon` y la
    // búsqueda fallaría de una forma que parece «no existe». En el body no hay ese borde.
    if (req.method !== "POST") {
      throw new AppError(405, "method_not_allowed", "Usa POST");
    }

    const { userId: viewerId } = await requireAuthUser(req);
    const service = getServiceRoleClient();

    // --- El tope diario (ADR 0028 §5).
    //
    // VA AQUÍ, ANTES DE MIRAR EL BODY, Y EL SITIO ES LA MITAD DE LA REGLA. El cupo cuenta
    // PETICIONES AL ENDPOINT, no búsquedas con éxito: si se incrementara después de resolver —o
    // solo al fallar— el propio contador distinguiría un tag inexistente de uno encontrado, y sería
    // el oráculo que `RN-23` existe para cerrar. Lo que se paga por ponerlo tan pronto es que una
    // petición con el body roto también gasta cupo; es el lado correcto en el que equivocarse.
    //
    // SE INCREMENTA PRIMERO Y SE DECIDE DESPUÉS, con el valor devuelto — igual que el tope de
    // refrescos de `connect-feed`. Al revés hay una ventana en la que dos peticiones leen el mismo
    // número y las dos pasan.
    const { data: usedToday, error: bumpError } = await service.rpc("bump_tag_lookup", {
      p_user_id: viewerId,
    });

    if (bumpError) {
      throw new AppError(500, "internal_error", "No se pudo buscar el tag", {
        cause: bumpError.message,
      });
    }

    // El RPC devuelve el total YA contando esta búsqueda, y el veredicto razona sobre las gastadas
    // ANTES — de ahí el `- 1`. Es el precio de incrementar primero.
    const verdict = evaluateTagLookupLimit((usedToday as number) - 1, new Date());
    if (!verdict.allowed) {
      // RN-21: el límite concreto y cuándo se recupera. Nunca un fallo mudo, y nunca un 404 — un
      // 404 aquí diría «ese tag no existe» cuando lo cierto es «hoy ya no puedes buscar más», y
      // sería mentirle al usuario sobre alguien que quizá sí está.
      throw new AppError(429, "rate_limited", "Has alcanzado el máximo de búsquedas por hoy", {
        limit: verdict.limit,
        retry_at: verdict.retryAt?.toISOString() ?? null,
      });
    }

    let body: LookupBody;
    try {
      body = (await req.json()) as LookupBody;
    } catch {
      throw new AppError(400, "invalid_input", "Body JSON inválido");
    }

    const tag = typeof body.tag === "string" ? body.tag.trim() : "";
    if (tag.length === 0) {
      throw new AppError(400, "invalid_input", "`tag` es obligatorio", { field: "tag" });
    }

    // Un tag con formato imposible es «no existe», NO un 400 de validación. Un 400 diría «ese
    // formato no puede existir» y un 404 «no hay nadie con ese tag»: la diferencia no filtra nada
    // aquí, pero mantener un solo desenlace para «no lo vas a encontrar» evita que mañana alguien
    // razone sobre dos. `isValidTag` es el espejo del `check` de la migración `20260823120000`.
    if (!isValidTag(tag)) notFound();

    const { data: profile, error: profileError } = await service
      .from("profiles")
      .select("user_id, display_name, tag, bio, preset_avatar, photo_path, time_helping_seconds, streak_days")
      .eq("tag", tag)
      .maybeSingle();

    if (profileError) {
      throw new AppError(500, "internal_error", "No se pudo buscar el tag", {
        cause: profileError.message,
      });
    }

    const targetId = (profile?.user_id as string | undefined) ?? null;

    // Solo si hay a quién mirar. Con `targetId` nulo no hay nada que consultar y la respuesta ya
    // está decidida.
    let blocked = false;
    let followStatus: "pending" | "accepted" | null = null;

    if (targetId !== null && targetId !== viewerId) {
      const [blocksRes, followRes] = await Promise.all([
        // Las DOS direcciones (RN-24, RN-47(2)). Sin la mitad «me bloqueó a mí», el bloqueado
        // encontraría el tag del bloqueador y podría mandarle una solicitud de seguimiento.
        service
          .from("blocks")
          .select("blocker_id")
          .or(
            `and(blocker_id.eq.${viewerId},blocked_id.eq.${targetId}),` +
              `and(blocker_id.eq.${targetId},blocked_id.eq.${viewerId})`,
          )
          .limit(1),
        service
          .from("user_follows")
          .select("status")
          .eq("follower_id", viewerId)
          .eq("followee_id", targetId)
          .maybeSingle(),
      ]);

      if (blocksRes.error) {
        throw new AppError(500, "internal_error", "No se pudo buscar el tag", {
          cause: blocksRes.error.message,
        });
      }
      if (followRes.error) {
        throw new AppError(500, "internal_error", "No se pudo buscar el tag", {
          cause: followRes.error.message,
        });
      }

      blocked = (blocksRes.data ?? []).length > 0;
      followStatus = (followRes.data?.status as "pending" | "accepted" | undefined) ?? null;
    }

    const outcome = resolveTagLookup({ viewerId, profileUserId: targetId, blocked, followStatus });

    if (outcome.kind === "not_found") notFound();

    if (outcome.kind === "self") {
      // El único desenlace que puede ser específico: quien pregunta ya sabe cuál es su tag, así
      // que decírselo no revela nada de nadie.
      throw new AppError(422, "own_tag", "Ese es tu propio tag");
    }

    // La misma lista de campos que `connect-feed`, y por la misma razón: es la frontera del Art. 9.
    // Ni un slug de categoría, ni `interests`, ni `suffered` ([ADR 0020]).
    return jsonResponse({
      user_id: outcome.userId,
      display_name: profile!.display_name,
      tag: profile!.tag,
      bio: profile!.bio,
      preset_avatar: profile!.preset_avatar,
      has_photo: profile!.photo_path !== null,
      time_helping_seconds: profile!.time_helping_seconds ?? 0,
      streak_days: profile!.streak_days ?? 0,
      // §6.2: el botón de la ficha depende de esto — `Seguir`, `Pendiente` o `Siguiendo`.
      follow_state: outcome.followState,
    }, 200);
  } catch (err) {
    return errorResponse(err);
  }
});
