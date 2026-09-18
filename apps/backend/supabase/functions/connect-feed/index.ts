// connect-feed — HTTP (app)
//
// El feed de Conectar (§6, §7). Sustituye a `match-feed`, que la Tarea 0 retiró (decisión 7 del
// plan): aquel declaraba "salas Y perfiles"; esto es solo perfiles, y las salas serán `rooms-feed`.
//
// ─────────────────────────────────────────────────────────────────────────────────────────────
// ESTA FUNCIÓN ES LA FRONTERA DEL ART. 9 RGPD, Y SU RESPUESTA SE AUDITA EN CADA REVISIÓN.
//
// Los tres ejes con los que puntúa —`onboarding_responses.responses`, `user_experiences` y
// `profiles_private.primary_category_id`/`secondary_categories`— son el MISMO catálogo de salud
// mental: «Ansiedad y estrés», «Duelo», «He perdido a alguien». Son categoría especial del Art. 9
// y hoy están cerrados incluso al propio usuario.
//
// Entran aquí, se convierten en UN NÚMERO dentro de `connect-scoring.ts`, y el número se usa para
// muestrear. NI UN SLUG, NI UN ID DE CATEGORÍA, NI EL DESGLOSE POR EJE salen en la respuesta. Lo
// que viaja son las cuatro señales NO sensibles de la decisión 1 del plan: perfil de oyente
// (preferencia de estilo, no condición), tiempo escuchando y racha (ya públicas en `profiles`).
//
// Si un día esta respuesta devuelve una categoría de otra persona, está mal — no «es discutible».
// [ADR 0020](docs/decisions/0020-conectar-no-muestra-datos-del-articulo-9.md).
// ─────────────────────────────────────────────────────────────────────────────────────────────
//
// Requiere service_role: sí. Lee `profiles_private` y `user_experiences` de OTRAS personas, que
// son read-own para el cliente; y escribe `connect_impressions`, que no tiene grants para
// `authenticated` (migración `20260823120400`, deny by default).
import { handleCorsPreflight } from "../_shared/cors.ts";
import { AppError, errorResponse, jsonResponse } from "../_shared/http.ts";
import { getServiceRoleClient, requireAuthUser } from "../_shared/supabase-client.ts";
import {
  type ConnectAxes,
  type ConnectCandidate,
  type ConnectFilter,
  selectConnectBatch,
} from "../_shared/connect-scoring.ts";
import { type ConnectExclusionSets, exclusionReason } from "../_shared/connect-exclusions.ts";
import { evaluateRefreshLimit } from "../_shared/connect-refresh.ts";
import { listenerProfileName } from "../_shared/onboarding-catalogs.ts";
import { MAX_POOL } from "../_shared/connect-pool.ts";

// `MAX_POOL` se importa y NO se declara aquí: desde el ADR 0030 lo vigila también el digest diario,
// y dos copias del mismo número divergirían sin que nada lo delate. Su documentación entera —qué
// significa el tope hoy y por qué ya no sesga— vive en `_shared/connect-pool.ts`.

/** Los chips del §6.3 (`Todos` es no mandar ninguno — RN-35). */
const FILTER_VALUES: readonly ConnectFilter[] = ["age", "interests", "suffered", "current"];

interface FeedBody {
  filters?: unknown;
  refresh?: unknown;
}

/** Fila ligera del pool: lo mínimo para excluir y para pintar la tarjeta. */
interface PoolRow {
  user_id: string;
  display_name: string | null;
  tag: string;
  bio: string | null;
  preset_avatar: string | null;
  photo_path: string | null;
  time_helping_seconds: number | null;
  streak_days: number | null;
}

function parseFilters(raw: unknown): ReadonlySet<ConnectFilter> {
  if (raw === undefined || raw === null) return new Set();
  if (!Array.isArray(raw)) {
    throw new AppError(400, "invalid_input", "`filters` debe ser un array", { field: "filters" });
  }
  const out = new Set<ConnectFilter>();
  for (const value of raw) {
    // RN-36: `Todos` desactiva el resto, así que el cliente lo manda como lista vacía y aquí se
    // acepta explícitamente por si lo envía como valor.
    if (value === "all") continue;
    if (!FILTER_VALUES.includes(value as ConnectFilter)) {
      throw new AppError(400, "invalid_input", "`filters` contiene un chip desconocido", {
        field: "filters",
        allowed: [...FILTER_VALUES, "all"],
      });
    }
    out.add(value as ConnectFilter);
  }
  return out;
}

/** Edad en años a partir de `birth_date`. */
function ageFrom(birthDate: string | null, now: Date): number | null {
  if (!birthDate) return null;
  const born = new Date(`${birthDate}T00:00:00.000Z`);
  if (Number.isNaN(born.getTime())) return null;

  let age = now.getUTCFullYear() - born.getUTCFullYear();
  const month = now.getUTCMonth() - born.getUTCMonth();
  if (month < 0 || (month === 0 && now.getUTCDate() < born.getUTCDate())) age -= 1;
  return age >= 0 && age < 130 ? age : null;
}

Deno.serve(async (req: Request) => {
  const preflight = handleCorsPreflight(req);
  if (preflight) return preflight;

  try {
    // POST y no GET aunque sea una lectura: cada llamada ESCRIBE (`connect_impressions` siempre, y
    // `connect_feed_runs` en un refresco). Un GET que muta se cachea en cualquier proxy y devuelve
    // la tanda de ayer.
    if (req.method !== "POST") {
      throw new AppError(405, "method_not_allowed", "Usa POST");
    }

    const { userId: viewerId, client: userClient } = await requireAuthUser(req);
    const service = getServiceRoleClient();

    let body: FeedBody;
    try {
      body = (await req.json()) as FeedBody;
    } catch {
      body = {};
    }

    const filters = parseFilters(body.filters);
    const isRefresh = body.refresh === true;
    const now = new Date();
    const today = now.toISOString().slice(0, 10);

    // --- 1) RN-46: el tope de 5 refrescos diarios.
    //
    // SE INCREMENTA PRIMERO Y SE DECIDE DESPUÉS, con el valor devuelto. Al revés —comprobar y
    // luego incrementar— hay una ventana en la que dos peticiones leen el mismo número y las dos
    // pasan. El RPC hace las dos cosas en una sola sentencia (migración `20260825130000`).
    if (isRefresh) {
      const { data: used, error: bumpError } = await service.rpc("bump_connect_refresh", {
        p_user_id: viewerId,
      });

      if (bumpError) {
        throw new AppError(500, "internal_error", "No se pudo contar el refresco", {
          cause: bumpError.message,
        });
      }

      // El RPC devuelve el total YA contando este intento, y el veredicto razona sobre los
      // gastados ANTES — de ahí el `- 1`. Es el precio de incrementar primero.
      const verdict = evaluateRefreshLimit((used as number) - 1, now);
      if (!verdict.allowed) {
        // RN-21: el límite concreto y cuándo se recupera. Nunca un fallo mudo ni un 500.
        throw new AppError(
          422,
          "refresh_limit_reached",
          "Has alcanzado el máximo de actualizaciones por hoy",
          {
            limit: verdict.limit,
            retry_at: verdict.retryAt?.toISOString() ?? null,
          },
        );
      }
    }

    // --- 2) Los ejes del espectador. Los tres son Art. 9 y no salen de esta función.
    const [privateRes, onboardingRes, experiencesRes] = await Promise.all([
      service
        .from("profiles_private")
        .select("birth_date, primary_category_id, secondary_categories")
        .eq("user_id", viewerId)
        .maybeSingle(),
      service.from("onboarding_responses").select("responses").eq("user_id", viewerId).maybeSingle(),
      service.from("user_experiences").select("experience_case_id").eq("user_id", viewerId),
    ]);

    for (const res of [privateRes, onboardingRes, experiencesRes]) {
      if (res.error) {
        throw new AppError(500, "internal_error", "No se pudo cargar tu perfil", {
          cause: res.error.message,
        });
      }
    }

    const viewerPrivate = privateRes.data as
      | { birth_date: string | null; primary_category_id: string | null; secondary_categories: string[] | null }
      | null;
    const viewerResponses =
      (onboardingRes.data?.responses ?? {}) as { interests?: unknown };

    const viewer: ConnectAxes = {
      // `birth_date`, que es la única fuente de verdad de la edad. Hubo una columna
      // `profiles_private.age` que no escribía nadie —siempre NULL—; usarla habría dejado `M_edad`
      // valiendo 1.0 para todo el mundo, en silencio y para siempre, y un multiplicador roto y uno
      // correcto son el mismo número. La borró la Tarea 24 (ADR 0025).
      //
      // `ageFrom` tiene un ESPEJO EN SQL: `public.age_in_years()`, que alimenta la vista
      // `public_profiles` del perfil ajeno. Los dos números se pintan en pantallas contiguas, así
      // que los dos calculan en UTC y se tocan a la vez.
      ageYears: ageFrom(viewerPrivate?.birth_date ?? null, now),
      interests: Array.isArray(viewerResponses.interests)
        ? (viewerResponses.interests as string[])
        : [],
      suffered: (experiencesRes.data ?? []).map((r) => r.experience_case_id as string),
      current: [
        viewerPrivate?.primary_category_id,
        ...(viewerPrivate?.secondary_categories ?? []),
      ].filter((v): v is string => typeof v === "string"),
    };

    // --- 3) Las exclusiones (RN-47, las seis, y la de RN-46).
    const [blocksRes, conversationsRes, followsRes, dismissalsRes, impressionsRes] = await Promise
      .all([
        // Las DOS direcciones en una consulta: RN-47(2). La mitad que se olvida es la de quien te
        // bloqueó a ti, que no se ve desde tu propia lista (`blocks` solo lo lee su `blocker_id`).
        service
          .from("blocks")
          .select("blocker_id, blocked_id")
          .or(`blocker_id.eq.${viewerId},blocked_id.eq.${viewerId}`),
        service
          .from("conversations")
          .select("user_a_id, user_b_id, status, initiator_id")
          .or(`user_a_id.eq.${viewerId},user_b_id.eq.${viewerId}`),
        service.from("user_follows").select("followee_id").eq("follower_id", viewerId),
        service.from("connect_dismissals").select("dismissed_user_id").eq("user_id", viewerId),
        service
          .from("connect_impressions")
          .select("shown_user_id")
          .eq("user_id", viewerId)
          .eq("shown_on", today),
      ]);

    for (const res of [blocksRes, conversationsRes, followsRes, dismissalsRes, impressionsRes]) {
      if (res.error) {
        throw new AppError(500, "internal_error", "No se pudo cargar el feed", {
          cause: res.error.message,
        });
      }
    }

    const blockedByViewer = new Set<string>();
    const blockedTheViewer = new Set<string>();
    for (const row of blocksRes.data ?? []) {
      if (row.blocker_id === viewerId) blockedByViewer.add(row.blocked_id as string);
      else blockedTheViewer.add(row.blocker_id as string);
    }

    // RN-47(3) es «conversación en CUALQUIER estado», y (4) son las solicitudes pendientes por
    // dirección. La segunda está contenida en la primera, pero se llenan las dos: la spec las
    // enumera por separado y el motivo de exclusión sirve para depurar el feed.
    const conversations = new Set<string>();
    const pendingRequestsSent = new Set<string>();
    const pendingRequestsReceived = new Set<string>();
    for (const row of conversationsRes.data ?? []) {
      const other = row.user_a_id === viewerId
        ? (row.user_b_id as string)
        : (row.user_a_id as string);
      conversations.add(other);
      if (row.status === "pending") {
        if (row.initiator_id === viewerId) pendingRequestsSent.add(other);
        else pendingRequestsReceived.add(other);
      }
    }

    const sets: ConnectExclusionSets = {
      viewerId,
      blockedByViewer,
      blockedTheViewer,
      conversations,
      pendingRequestsSent,
      pendingRequestsReceived,
      following: new Set((followsRes.data ?? []).map((r) => r.followee_id as string)),
      dismissed: new Set((dismissalsRes.data ?? []).map((r) => r.dismissed_user_id as string)),
      shownToday: new Set((impressionsRes.data ?? []).map((r) => r.shown_user_id as string)),
    };

    // --- 4) El pool: una muestra ALEATORIA de elegibles, ya excluida en SQL.
    //
    // Antes esto era `.from("profiles").select(...).limit(MAX_POOL)` sobre la tabla SIN filtrar, y
    // las exclusiones se aplicaban después. Eso producía los dos síntomas del punto 16 de
    // `docs/pending-messaging.md`: la muestra era siempre LA MISMA —sesgo hacia quien estuviera
    // antes en el índice— y podía dar `empty_state` habiendo candidatos, porque si esas 1000 filas
    // crudas resultaban todas excluidas nadie miraba más allá.
    //
    // El espectador va POR PARÁMETRO y no por `auth.uid()` dentro de la función: un RPC
    // personalizado con `auth.uid()` llamado con `service_role` devuelve la respuesta del anónimo y
    // no da error (punto 11 de la skill `edge-functions`). La contrapartida es que la función tiene
    // el `execute` revocado a `authenticated`, o el parámetro sería un agujero.
    const { data: poolRows, error: poolError } = await service.rpc("connect_eligible_sample", {
      p_viewer: viewerId,
      p_limit: MAX_POOL,
    });

    if (poolError) {
      throw new AppError(500, "internal_error", "No se pudo cargar el feed", {
        cause: poolError.message,
      });
    }

    // Las exclusiones se aplican DOS veces: aquí sobre lo que ya excluyó SQL, y otra vez dentro de
    // `selectConnectBatch`, que es la autoritativa. Es deliberado — filtrar aquí y luego pasar
    // conjuntos vacíos ahorraría un recorrido y abriría el agujero que `RN-49` cierra: relajar el
    // filtro no relaja las exclusiones. Aplicarlas dos veces es idempotente y cuesta nada.
    // Se usa `exclusionReason` y no `applyExclusions` porque estas filas vienen de Postgres con
    // `user_id`, no con el `userId` del dominio. Es la MISMA primitiva probada, sin una capa de
    // renombrado que solo existiría para satisfacer una firma.
    const eligibleRows = ((poolRows ?? []) as PoolRow[]).filter(
      (row) => exclusionReason(row.user_id, sets) === null,
    );

    if (eligibleRows.length === 0) {
      // RN-49: nunca una lista vacía sin explicación.
      return jsonResponse({ candidates: [], empty_state: true, relaxed: false }, 200);
    }

    const eligibleIds = eligibleRows.map((r) => r.user_id);

    // --- 5) Los ejes de los candidatos. AQUÍ ENTRA EL ART. 9, y no vuelve a salir.
    const [candPrivateRes, candOnboardingRes, candExperiencesRes] = await Promise.all([
      service
        .from("profiles_private")
        .select("user_id, birth_date, primary_category_id, secondary_categories")
        .in("user_id", eligibleIds),
      service.from("onboarding_responses").select("user_id, responses").in("user_id", eligibleIds),
      service.from("user_experiences").select("user_id, experience_case_id").in("user_id", eligibleIds),
    ]);

    for (const res of [candPrivateRes, candOnboardingRes, candExperiencesRes]) {
      if (res.error) {
        throw new AppError(500, "internal_error", "No se pudo puntuar el feed", {
          cause: res.error.message,
        });
      }
    }

    const privateById = new Map(
      (candPrivateRes.data ?? []).map((r) => [r.user_id as string, r]),
    );
    const responsesById = new Map(
      (candOnboardingRes.data ?? []).map((r) => [
        r.user_id as string,
        (r.responses ?? {}) as { interests?: unknown; profile?: unknown },
      ]),
    );
    const experiencesById = new Map<string, string[]>();
    for (const row of candExperiencesRes.data ?? []) {
      const id = row.user_id as string;
      const list = experiencesById.get(id) ?? [];
      list.push(row.experience_case_id as string);
      experiencesById.set(id, list);
    }

    const candidates: ConnectCandidate[] = eligibleRows.map((row) => {
      const priv = privateById.get(row.user_id);
      const responses = responsesById.get(row.user_id) ?? {};
      return {
        userId: row.user_id,
        ageYears: ageFrom((priv?.birth_date as string | null) ?? null, now),
        interests: Array.isArray(responses.interests) ? (responses.interests as string[]) : [],
        suffered: experiencesById.get(row.user_id) ?? [],
        current: [
          priv?.primary_category_id as string | undefined,
          ...((priv?.secondary_categories as string[] | null) ?? []),
        ].filter((v): v is string => typeof v === "string"),
      };
    });

    // --- 6) Puntuar y muestrear (RN-42, RN-44, RN-49). `Math.random` entra aquí y solo aquí: la
    // lógica es pura y recibe el azar por parámetro, que es lo que la hace testeable.
    const batch = selectConnectBatch(viewer, candidates, sets, filters, Math.random);

    if (batch.kind === "empty") {
      return jsonResponse({ candidates: [], empty_state: true, relaxed: false }, 200);
    }

    const chosen = batch.candidates;
    const chosenIds = chosen.map((c) => c.userId);
    const rowById = new Map(eligibleRows.map((r) => [r.user_id, r]));

    // --- 7) RN-46: registrar la tanda. Sin esto, el siguiente refresco repetiría a los mismos, y
    // el scroll infinito no avanzaría. `ignoreDuplicates` porque la PK ya lleva la fecha dentro.
    const { error: impressionError } = await service
      .from("connect_impressions")
      .upsert(
        chosenIds.map((shown_user_id) => ({ user_id: viewerId, shown_user_id, shown_on: today })),
        { onConflict: "user_id,shown_user_id,shown_on", ignoreDuplicates: true },
      );

    if (impressionError) {
      // No se lanza: la tanda ya está calculada y devolverla es mejor que perderla. El coste de no
      // registrarla es que alguien pueda repetirse, no una fuga ni una inconsistencia.
      console.warn("connect_impressions upsert failed:", impressionError.message);
    }

    // --- 8) El punto de actividad. CON EL CLIENTE DEL USUARIO, NO CON EL DE SERVICIO.
    //
    // `activity_status` deriva quién pregunta de `auth.uid()`, que con la clave de servicio es
    // NULL: devolvería `false` para todo el mundo SIN DAR ERROR, y todos los puntos saldrían en
    // gris en silencio y para siempre. Además RN-32 es recíproco —quien oculta su actividad no ve
    // la de nadie— y eso solo se puede resolver sabiendo quién llama.
    // Precedente: skill `edge-functions`, punto 11.
    const activeById = new Map<string, boolean>();
    if (chosenIds.length > 0) {
      const { data: activity, error: activityError } = await userClient.rpc("activity_status", {
        p_user_ids: chosenIds,
      });
      if (activityError) {
        console.warn("activity_status failed:", activityError.message);
      } else {
        for (const row of activity ?? []) {
          activeById.set(row.user_id as string, row.is_active as boolean);
        }
      }
    }

    // --- 9) La respuesta. LA LISTA DE CAMPOS ES LA FRONTERA DEL ART. 9: lo que no esté aquí, no
    // sale. Ni `interests`, ni `suffered`, ni `current`, ni el `ScoreBreakdown` que los resume.
    return jsonResponse({
      candidates: chosen.map((c) => {
        const row = rowById.get(c.userId)!;
        const responses = responsesById.get(c.userId) ?? {};
        return {
          user_id: c.userId,
          display_name: row.display_name,
          tag: row.tag,
          age: c.ageYears,
          bio: row.bio,
          preset_avatar: row.preset_avatar,
          // La foto NO viaja: su URL la firma `profile-photo-view-url` contra R2 (skill
          // `media-storage`). Se dice si la hay para no pedir 20 firmas a ciegas.
          has_photo: row.photo_path !== null,
          is_active: activeById.get(c.userId) ?? false,
          // Las tres señales NO sensibles de la decisión 1. `profile` es el perfil de oyente
          // («empático y cercano»): una preferencia de ESTILO, no una condición de salud.
          //
          // Va **traducido a su nombre**, no el slug: `onboarding_responses` guarda `slug` —el
          // cliente manda `slug` al completar el onboarding— y devolverlo crudo hacía que la
          // tarjeta pintara «empatico-cercano», un identificador interno. Un slug que el catálogo
          // no conozca sale como `null` y la tarjeta se queda sin ese chip.
          listener_profile: listenerProfileName(responses.profile),
          time_helping_seconds: row.time_helping_seconds ?? 0,
          streak_days: row.streak_days ?? 0,
        };
      }),
      empty_state: false,
      // RN-49: la tanda se sirvió sin el cuadrado del filtro por haber pocos candidatos. La UI
      // puede decirlo; no es un error.
      relaxed: batch.kind === "relaxed",
    }, 200);
  } catch (err) {
    return errorResponse(err);
  }
});
