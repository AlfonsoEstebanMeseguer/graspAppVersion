# onboarding-catalogs

Trigger: HTTP (app), `GET`. Devuelve los catálogos de opciones del cuestionario de alta
(categorías, casos concretos, perfiles de oyente, fuentes de descubrimiento) para que Flutter deje
de tener el catálogo de slugs hardcodeado en `onboarding_question.dart`. No forma parte de la
Sección 11 del documento maestro; se añadió en el ciclo de corrección post-Bloque 2 (auditoría de
contrato roto entre `onboarding-complete` y el cliente) como la contrapartida de lectura del
contrato que valida `onboarding-complete`. Ver `docs/api-contracts.md` § Bloque 2.