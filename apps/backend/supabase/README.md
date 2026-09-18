# apps/backend/supabase

Placeholder de estructura. `config.toml` y `seed.sql` todavía NO se han generado — se crean con `supabase init`
tras instalar la Supabase CLI (ver `docs/Grasp-Fase1.md` § Bloque 0). El proyecto Supabase remoto ya existe y
está enlazado vía MCP (`project_ref=epmjveozxrwuocusvyay`), pendiente de `supabase link` local.

- `migrations/` — SQL versionado, ver su propio README.
- `functions/` — una carpeta por Edge Function, contrato completo en `docs/api-contracts.md` (Sección 11 del
  documento maestro).
- `seed.sql` (pendiente) — categorías iniciales (Sección 4) + `gift_catalog` (Sección 15).
