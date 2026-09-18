# onboarding-complete

Trigger: HTTP (app). Valida respuestas, guarda `onboarding_responses` (auditoría), sincroniza
`user_experiences` y actualiza `profiles_private.primary_category_id` / `secondary_categories` (esta
última derivada de las categorías de las experiencias elegidas, no enviada por el cliente). Ver
Sección 11 del documento maestro, `docs/Grasp-Fase1.md` § Bloque 2 y el contrato completo en
`docs/api-contracts.md` § Bloque 2.

Requiere `service_role`: escribe `user_experiences`, que no tiene policy de escritura para el
usuario (dato de salud, Art. 9 RGPD).

Catálogo de opciones (`categories`, `experience_cases`, perfiles de oyente, fuentes de
descubrimiento) disponible vía `onboarding-catalogs`, no hardcodeado en el cliente.

**Pendiente de infraestructura**: sin desplegar todavía — el entorno de desarrollo no tiene
`supabase link` hecho (`LegacyProjectNotLinkedError`). El seed de catálogos
(`20260809120100_seed_catalogs.sql`) ya existe, así que esa dependencia previa está resuelta.