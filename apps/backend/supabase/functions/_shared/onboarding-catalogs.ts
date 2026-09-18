// Catálogos hardcodeados del onboarding que no tienen tabla propia en BD.
//
// `categories` y `experience_cases` sí son tablas (Bloque 2, migración
// `20260809120000_bloque2_badges_experiences_and_column_grants.sql`) porque alimentan el
// algoritmo de afinidad (`match-feed`) con datos que el cliente no puede falsificar. Los dos
// catálogos de aquí no son entrada del matching — son metadatos de perfil/analítica — así que no
// justifican una tabla ni una migración: viven en código, versionados igual que cualquier otra
// constante de negocio. Si en el futuro entran en el scoring de `match-feed`, se promueven a
// tabla (mismo motivo por el que `experience_cases` sí es tabla y esto no).
//
// Se comparte entre `onboarding-complete` (valida contra esto) y `onboarding-catalogs` (lo expone
// al cliente) para que nunca puedan divergir.
export interface CatalogOption {
  slug: string;
  name: string;
}

export const LISTENER_PROFILES: CatalogOption[] = [
  { slug: "empatico-cercano", name: "Empático y cercano" },
  { slug: "directo-practico", name: "Directo y práctico" },
  { slug: "espiritual-reflexivo", name: "Espiritual y reflexivo" },
  { slug: "experiencia-similar", name: "Con experiencia similar" },
  { slug: "formacion-profesional", name: "Con formación profesional" },
  { slug: "cualquiera", name: "Cualquiera, lo que mejor encaje" },
];

/**
 * El **nombre** de un perfil de oyente a partir de su slug, o `null` si no está en el catálogo.
 *
 * ## Por qué hace falta, y dónde se notaba que faltaba
 *
 * `onboarding_responses.responses.profile` guarda el **slug**: el cliente manda `slug` al completar
 * el onboarding, no `name`. `connect-feed` lo devolvía crudo en `listener_profile` y la tarjeta de
 * Conectar pintaba «empatico-cercano» tal cual — un identificador interno donde el ADR 0020 pide
 * una **señal legible**. No lo vio ningún test: se vio en el emulador.
 *
 * **Un slug desconocido devuelve `null`, nunca el slug.** Usarlo como respaldo sería peor que no
 * pintar nada: acabaría igualmente en la pantalla de alguien. Si el catálogo cambia y una respuesta
 * vieja deja de resolverse, la tarjeta se queda sin ese chip y ya está.
 */
export function listenerProfileName(slug: unknown): string | null {
  if (typeof slug !== "string") return null;
  return LISTENER_PROFILES.find((o) => o.slug === slug)?.name ?? null;
}

export const DISCOVERY_SOURCES: CatalogOption[] = [
  { slug: "redes-sociales", name: "Redes sociales" },
  { slug: "amigo-familiar", name: "Un amigo o familiar" },
  { slug: "busqueda-tienda", name: "Búsqueda en la tienda" },
  { slug: "publicidad", name: "Publicidad" },
  { slug: "otro", name: "Otro" },
];

export function isKnownSlug(catalog: CatalogOption[], slug: string): boolean {
  return catalog.some((option) => option.slug === slug);
}
