// Lógica pura del tope de rotación del tag (RN-21). PURA: sin red, sin Postgres, sin reloj propio
// — `now` entra por parámetro, que es lo que hace que los bordes se puedan testear sin esperar 24 h.
//
// El acuñado del tag NO vive aquí: lo hace `public.mint_user_tag` dentro de la base de datos, y su
// espejo de formato es `_shared/tag.ts`. Este módulo solo decide SI se puede rotar y CUÁNDO se
// recupera el cupo.
import { AppError } from "./http.ts";

/**
 * Una rotación cada 24 h (§6.2: «puede solicitar un nuevo tag», con tope).
 *
 * El tope existe porque el tag es cómo te encuentra la gente: quien lo rota sin freno invalida el
 * identificador que sus contactos habían guardado, y de paso convierte el índice único en un
 * juguete para acaparar partes locales.
 */
export const TAG_ROTATION_COOLDOWN_MS = 24 * 60 * 60 * 1000;

export interface RotationDecision {
  allowed: boolean;
  /** Instante exacto en que se recupera el cupo. `null` cuando `allowed` es `true`. */
  retryAt: Date | null;
}

/**
 * Decide si se puede rotar el tag, y si no, cuándo se podrá.
 *
 * @param lastRotatedAt `profiles_private.tag_rotated_at`; `null`/`undefined` = nunca ha rotado.
 * @param now Instante de la petición.
 *
 * Tres decisiones que no son obvias:
 *
 * · **A las 24 h EN PUNTO ya hay cupo** (`>=`, no `>`). Es el off-by-one clásico de un tope, y RN-01
 *   demuestra que en este proyecto importa: la spec subraya que el quinto mensaje SÍ pasa.
 *
 * · **Una marca en el FUTURO bloquea** en vez de permitir. Puede venir de un desfase de reloj o de
 *   una fila tocada a mano; bloquear de más es molesto, permitir de más anula el tope entero.
 *
 * · **Una fecha ilegible revienta** en lugar de permitir o bloquear en silencio, porque las dos
 *   opciones silenciosas esconden una fila corrupta. Es el freno que duda de los datos con los que
 *   decide, y ahí CLAUDE.md manda abortar.
 */
export function evaluateTagRotation(
  lastRotatedAt: string | Date | null | undefined,
  now: Date,
): RotationDecision {
  if (lastRotatedAt === null || lastRotatedAt === undefined) {
    return { allowed: true, retryAt: null };
  }

  const last = lastRotatedAt instanceof Date ? lastRotatedAt : new Date(lastRotatedAt);
  if (Number.isNaN(last.getTime())) {
    throw new AppError(500, "internal_error", "tag_rotated_at no es una fecha válida");
  }

  const retryAt = new Date(last.getTime() + TAG_ROTATION_COOLDOWN_MS);
  if (now.getTime() >= retryAt.getTime()) {
    return { allowed: true, retryAt: null };
  }

  return { allowed: false, retryAt };
}
