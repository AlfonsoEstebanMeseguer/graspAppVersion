// Búsqueda por tag (§6.2): los cuatro desenlaces, como decisión pura.
// PURA: sin red y sin Postgres — recibe lo que el handler ya consultó y devuelve qué se responde.
//
// ─────────────────────────────────────────────────────────────────────────────────────────────
// POR QUÉ ESTO NO VIVE DENTRO DEL HANDLER. La regla que sostiene esta pantalla —«el tag de alguien
// con bloqueo en cualquier dirección responde igual que si no existiera»— es una comparación entre
// DOS respuestas, y una comparación no se puede probar mirando una sola rama de un `if`. Aquí las
// dos son valores, y el test las compara con `assertEquals`: si alguien añade mañana un
// `{ kind: "not_found", reason: "blocked" }` para depurar, el test cae en vez de filtrarse a
// producción.
// ─────────────────────────────────────────────────────────────────────────────────────────────

/** Estado del follow del espectador **hacia** el perfil encontrado. */
export type FollowState = "none" | "pending" | "following";

export interface TagLookupInput {
  viewerId: string;
  /** `null` si ningún perfil tiene ese tag. */
  profileUserId: string | null;
  /** Bloqueo en **cualquier** dirección, ya unido por el handler. */
  blocked: boolean;
  /** Fila de `user_follows` del espectador hacia el perfil, si existe. */
  followStatus: "pending" | "accepted" | null;
}

export type TagLookupOutcome =
  | { kind: "not_found" }
  | { kind: "self" }
  | { kind: "found"; userId: string; followState: FollowState };

/** El único valor de «no existe». Uno solo, para que no haya dos que puedan divergir. */
const NOT_FOUND: TagLookupOutcome = { kind: "not_found" };

export function resolveTagLookup(input: TagLookupInput): TagLookupOutcome {
  // --- Nadie tiene ese tag.
  if (input.profileUserId === null) return NOT_FOUND;

  // --- Tu propio tag. Va ANTES del bloqueo, aunque `blocks_no_self` haga imposible el cruce: si
  // alguien relajara esa constraint, es mejor que te digan «es el tuyo» que esconderte de ti mismo.
  // Es el único de los cuatro desenlaces que puede ser específico sin revelar nada: quien pregunta
  // ya sabe cuál es su tag.
  if (input.profileUserId === input.viewerId) return { kind: "self" };

  // --- BLOQUEO: se devuelve EL MISMO VALOR que «no existe», no uno parecido.
  //
  // Y se comprueba antes de mirar el follow a propósito. Un follow aceptado con bloqueo por medio
  // devolvería `following`, y eso confirmaría que la cuenta existe — el dato que §6.2 esconde.
  if (input.blocked) return NOT_FOUND;

  return {
    kind: "found",
    userId: input.profileUserId,
    followState: input.followStatus === "accepted"
      ? "following"
      : input.followStatus === "pending"
      ? "pending"
      : "none",
  };
}
