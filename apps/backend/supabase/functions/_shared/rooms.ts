// Constantes y lógica pura de las salas (Fase 5).
//
// MAX_OCCUPANTS (20) y MAX_SPEAKERS (2) son aquí un ESPEJO DECLARADO SOLO PARA
// PINTAR LÍMITES EN EL CLIENTE. La fuente de verdad es Postgres: las funciones
// `public.room_max_occupants()` y `public.room_max_speakers()` en
// `20260901120000_rooms.sql`. Se comprueban dentro de la misma transacción que
// escribe en `room-actions`, garantizando atomicidad (§3.4 de
// docs/superpowers/specs/2026-08-31-salas-de-voz-fase5-design.md). Si algún día
// estas constantes divergen de Postgres, gana Postgres; no se usan para decidir
// si alguien entra en una sala.
//
// Los topes viven AQUÍ y solo aquí, como MAX_POOL en connect-pool.ts (ADR 0030):
// un literal repetido en dos funciones diverge en cuanto alguien toca una.

export const MAX_OCCUPANTS = 20;
export const MAX_SPEAKERS = 2;

/** Cuántos avatares caben en la cadena de la tarjeta (ADR 0032 § 4). */
export const CARD_AVATARS = 4;

export type CardParticipant = {
  userId: string;
  role: "host" | "speaker" | "listener";
  joinedAt: string;
};

/**
 * La cadena de avatares de la tarjeta: el escenario primero, luego los últimos
 * en entrar. El host se excluye — ya sale en grande a la izquierda.
 */
export function pickCardAvatars(
  participants: CardParticipant[],
  hostId: string,
  limit: number = CARD_AVATARS,
): { shown: CardParticipant[]; overflow: number } {
  const candidates = participants.filter((p) => p.userId !== hostId);

  const ordered = [...candidates].sort((a, b) => {
    const aStage = a.role === "speaker" ? 0 : 1;
    const bStage = b.role === "speaker" ? 0 : 1;
    if (aStage !== bStage) return aStage - bStage;

    // Comparar por instante, no por cadena: `joinedAt` llega de Postgres
    // como timestamptz y su forma exacta varía (Z vs. offset, microsegundos).
    // `localeCompare` es sensible al locale. `Date.parse()` normaliza.
    const aTime = Date.parse(a.joinedAt);
    const bTime = Date.parse(b.joinedAt);

    // Si alguno no es parseable, empujar al final (NaN < cualquier número es falso,
    // así que quedan al final).
    if (isNaN(aTime)) return 1;
    if (isNaN(bTime)) return -1;

    return bTime - aTime; // más reciente primero
  });

  const shown = ordered.slice(0, limit);
  return { shown, overflow: Math.max(0, ordered.length - shown.length) };
}
