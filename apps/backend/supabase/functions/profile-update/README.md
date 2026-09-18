# profile-update

Trigger: HTTP (app). Actualiza los campos editables de `profiles` (`display_name`) y
`profiles_private` (`birth_date`, `gender`, `country`) del usuario autenticado.

`phone_number` estuvo en esa lista y **ya no existe**: la columna se borró en `20260816090000`
(H-S-01, ADR 0015). La versión desplegada siguió escribiéndola hasta el redespliegue del
2026-08-23 — ver ADR 0019, § «las funciones desplegadas eran más viejas que el repositorio».
No está en la Sección 11 del documento maestro; se añadió en el Bloque 2 como base de la edición
de perfil del Bloque 3 (boceto `08-profile.jpeg`). Ver `docs/api-contracts.md` § Bloque 2.
