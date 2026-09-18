// rooms-feed — la lista de salas activas (ADR 0032). No se personaliza por gusto: solo por
// moderación (RN-23, ambas direcciones de bloqueo). Ver `docs/decisions/0032-el-feed-de-salas-no-se-personaliza.md`.
import { AppError, errorResponse, jsonResponse } from "../_shared/http.ts";
import { requireAuthUser } from "../_shared/supabase-client.ts";
import { type CardParticipant, pickCardAvatars } from "../_shared/rooms.ts";

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

type RoomRow = {
  id: string;
  title: string;
  category_id: string;
  host_id: string;
  host_name: string | null;
  host_photo_path: string | null;
  last_activity_at: string;
  occupants: number;
  participants: CardParticipant[] | null;
};

Deno.serve(async (req: Request): Promise<Response> => {
  try {
    if (req.method !== "GET") {
      throw new AppError(405, "method_not_allowed", "Método no permitido");
    }

    // El cliente del USUARIO, no `service_role`: el RPC filtra los bloqueos con `auth.uid()`.
    // Con la clave de servicio `auth.uid()` sale NULL y el filtro no filtraría nada, sin dar
    // ningún error (punto 11 de `edge-functions`) — por eso `rooms_feed` ni siquiera concede
    // `execute` a `service_role` (ver la migración `20260901120000_rooms.sql`).
    const { client } = await requireAuthUser(req);

    const categoryParam = new URL(req.url).searchParams.get("categoryId");
    let categoryId: string | null = null;
    if (categoryParam !== null && categoryParam !== "") {
      if (!UUID_RE.test(categoryParam)) {
        throw new AppError(400, "bad_category", "categoryId no es un uuid válido");
      }
      categoryId = categoryParam;
    }

    const { data, error } = await client.rpc("rooms_feed", { p_category: categoryId });
    if (error) throw error;

    const rows = (data ?? []) as RoomRow[];

    return jsonResponse({
      rooms: rows.map((r) => {
        const { shown, overflow } = pickCardAvatars(r.participants ?? [], r.host_id);
        return {
          id: r.id,
          title: r.title,
          categoryId: r.category_id,
          hostId: r.host_id,
          hostName: r.host_name,
          hostPhotoPath: r.host_photo_path,
          occupants: r.occupants,
          avatars: shown.map((s) => s.userId),
          overflow,
        };
      }),
    });
  } catch (err) {
    return errorResponse(err);
  }
});
