# migrations

SQL versionado. Convención: `<timestamp>_<descripcion>.sql`, snake_case, cada migración con su rollback,
timestamps en UTC. RLS obligatorio desde la misma migración que crea la tabla (ver skill `db-schema` y
`rls-security` en `.claude/skills/`).

## Estado actual: 3 migraciones (squash del 2026-08-16)

El 2026-08-16 se consolidaron las 19 migraciones del historial 20260808–20260816 en 3, con producción
prácticamente vacía (1 perfil, 0 fotos — `docs/audits/2026-08-13-p0-despliegue-y-e2e-produccion.md:31`) y
con la equivalencia probada por diff, no afirmada. Decisión completa, procedimiento de verificación y
procedimiento de reconciliación de producción: `docs/decisions/0017-consolidar-las-migraciones-en-tres.md`.

- `20260816120000_baseline_schema.sql` — extensiones no incluidas (van con los crons), tablas, índices,
  RLS + policies, grants por rol (`anon`/`authenticated`/`service_role`), funciones y triggers.
- `20260816120001_baseline_crons.sql` — extensiones `pg_cron`/`pg_net`, esquema `private`, token dedicado
  en Vault, envoltorios `pg_net` y los 4 `cron.schedule`.
- `20260816120002_baseline_seed_catalogs.sql` — catálogos (categorías, casos concretos, insignias).

Las 3 son **idempotentes**: pueden aplicarse tanto sobre una base vacía como sobre un entorno que ya tenga
este esquema (`create table if not exists`, `drop policy if exists` + `create policy`,
`create or replace function`, patrón revoke-total-y-reconceder-explícito en los grants, `cron.schedule`
hace upsert por nombre). Ver el procedimiento de reconciliación de producción en el ADR 0017.

**Las 19 migraciones viejas ya NO están en el repositorio** (se borraron en el mismo commit que introdujo
el baseline, tras probar la equivalencia). Su contenido completo sigue disponible en el historial de git:

```sh
git log --diff-filter=D --name-only -- apps/backend/supabase/migrations/2026080*.sql apps/backend/supabase/migrations/2026081[0-6]*.sql
git show <commit_del_squash>^:apps/backend/supabase/migrations/<nombre_de_la_migracion_vieja>.sql
```

## Tabla de correspondencia: migración vieja → qué hacía → dónde vive ahora

Los nombres de la columna izquierda son los que citan `CLAUDE.md`, las skills (`db-schema`,
`rls-security`) y los `docs/decisions/*.md` como precedentes. Siguen siendo válidos como referencia
histórica aunque el fichero ya no exista: lo que documentan (la causa raíz, la verificación empírica, el
incidente) no caducó, solo cambió de ubicación física.

| Migración vieja | Qué hacía | Dónde vive ahora |
|---|---|---|
| `20260808000000_schema_baseline_bloque1.sql` | `categories`, `profiles`, `profiles_private`, `handle_new_user` (versión que solo copiaba metadata) | `baseline_schema.sql` §§ 1–3, 13 (función reemplazada por la versión validadora de `20260816090000`) |
| `20260809000000_bloque2_onboarding_and_metrics.sql` | `onboarding_responses`, `set_updated_at`, `profiles.badges_count`/`experiences_count` (retiradas después) | `baseline_schema.sql` §§ 4, 13 |
| `20260809104229_add_storage_gc_queue.sql` | `storage_gc_queue`, `photo_audit_log`, trigger `profiles_on_delete_queue_photo` (con FK a `auth.users`, rota) | `baseline_schema.sql` §§ 9, 10, 13 (FK ya retirada, ver `20260810140000`) |
| `20260809120000_bloque2_badges_experiences_and_column_grants.sql` | `badges`, `user_badges`, `experience_cases`, `user_experiences`; primer grant de columna sobre `profiles`; retira `badges_count`/`experiences_count`, añade `rooms_joined_count` | `baseline_schema.sql` §§ 5–8, 2 (columna), 12 (grant ya normalizado por hotfixes posteriores) |
| `20260809120100_seed_catalogs.sql` | Siembra 12 categorías, 18 casos concretos, 10 insignias | `baseline_seed_catalogs.sql` completo |
| `20260809140854_revoke_photo_url_write_and_anon_update_on_profiles.sql` | Retira `photo_url` del grant de escritura de `authenticated`; revoca `UPDATE` de `anon` sobre `profiles` | `baseline_schema.sql` § 12 (estado final ya incorporado) |
| `20260809142046_lock_down_table_grants_for_anon_and_authenticated.sql` | Cierra `anon`/`authenticated` a nivel de tabla y de default privileges; primer grant explícito por tabla | `baseline_schema.sql` § 12 (patrón revoke-total-y-reconceder) |
| `20260809150000_add_photo_path_to_profiles.sql` | Añade `profiles.photo_path` | `baseline_schema.sql` § 2 (columna) |
| `20260810093000_grant_service_role_dml_on_public_tables.sql` | Primer grant de DML a `service_role` (BYPASSRLS ≠ BYPASSGRANT) | `baseline_schema.sql` § 12 (lista ya fusionada con `20260810160000`) |
| `20260810120000_schedule_media_gc_cron.sql` | `pg_cron`/`pg_net`, esquema `private`, primer envoltorio de `media-gc-cron` (autenticado con `service_role key`, versión rota) | `baseline_crons.sql` §§ 1–2, 4 (envoltorio reemplazado por la versión de `20260810170000`) |
| `20260810140000_fix_account_deletion_cascade.sql` | Retira las FK de `storage_gc_queue`/`photo_audit_log` contra `auth.users` (tablas lápida) | `baseline_schema.sql` §§ 9, 10 (ya sin FK desde el origen) |
| `20260810150000_add_retry_to_storage_gc_queue.sql` | `attempts`, `last_error`, `last_attempt_at`; sustituye el índice `idx_storage_gc_queue_status` por `idx_storage_gc_queue_pending` | `baseline_schema.sql` § 9 |
| `20260810160000_normalize_service_role_grants_and_harden_gc_trigger.sql` | Normaliza default privileges de `service_role` entre entornos; `search_path` fijo en `queue_profile_photo_for_deletion` | `baseline_schema.sql` §§ 12, 13 |
| `20260810170000_use_dedicated_token_for_internal_cron.sql` | Token dedicado en Vault; reescribe los envoltorios para usarlo en vez de la `service_role key` | `baseline_crons.sql` §§ 3–4 (versión final ya incorporada) |
| `20260810180000_add_media_reconcile_runs.sql` | `media_reconcile_runs` | `baseline_schema.sql` § 11 |
| `20260810190000_schedule_reconcile_and_digest_crons.sql` | Envoltorios y `cron.schedule` de `media-reconcile-cron` y `ops-digest-cron` | `baseline_crons.sql` §§ 4–5 |
| `20260812090000_add_photo_audit_retention.sql` | `cron.schedule` de `photo-audit-retention`; `grant select (created_at)` a `service_role` sobre `photo_audit_log` | `baseline_crons.sql` § 5 (cron) + `baseline_schema.sql` § 12 (grant de columna) |
| `20260813090000_add_preset_avatar_to_profiles.sql` | `profiles.preset_avatar`, constraints `profiles_preset_avatar_valid` y `profiles_avatar_exclusive` | `baseline_schema.sql` § 2 |
| `20260816090000_drop_phone_number_and_harden_signup.sql` | Borra `profiles.phone_number` y su índice (H-S-01); `handle_new_user` pasa a validar (H-SV-03); constraints `profiles_display_name_length_chk`/`profiles_private_gender_chk` | `baseline_schema.sql` §§ 2, 3, 13 (versión final ya incorporada) |

## ⚠️ El baseline ya NO es solo el squash (2026-08-17)

`20260816120000_baseline_schema.sql` incorpora, además del squash, el cambio del **ADR 0018**
(`display_name` obligatorio: `not null`, constraint reescrita con `btrim` y sin `not valid`, y
`handle_new_user` rechazando el alta sin nombre). Se fundió ahí a petición explícita del usuario en
vez de añadirse como migración nueva. Dos consecuencias que no se deducen leyendo el fichero:

- **El "Camino B" del ADR 0017 (reconciliar sin reconstruir) queda prohibido.** Su premisa —que el
  esquema del baseline ya está presente, construido por las 19 viejas— dejó de ser cierta. Producción
  solo puede ir por el **Camino A**: reconstruir desde cero. Sigue siendo viable (1 perfil, 0 fotos).
- **La prueba de equivalencia del ADR 0017 describe el fichero en el commit del squash**, no su estado
  actual. Para leerla contra su objeto real:
  `git show 0b2c7db:apps/backend/supabase/migrations/20260816120000_baseline_schema.sql`.

## `20260828120000_set_updated_at_search_path.sql`

Una línea: `alter function public.set_updated_at() set search_path = ''`. Cierra el único aviso del
advisor de Supabase que era un aviso de verdad (`function_search_path_mutable`); los otros cuatro son
deliberados y están explicados en
[`docs/audits/2026-08-28-humo-en-produccion-fase4.md`](../../../../docs/audits/2026-08-28-humo-en-produccion-fase4.md).
La función es `SECURITY INVOKER`, así que **no** había escalada de privilegios — el riesgo era un
`now()` sombreado escribiendo un `updated_at` falso. Se demostró mutando: con el `search_path`
anterior el trigger escribió `1999-01-01`. Aplicada a producción el 2026-08-28.

## Convención para migraciones futuras

A partir de `20260816120002`, las migraciones nuevas siguen el flujo normal: una por cambio, con su
rollback documentado. El squash es una excepción justificada por un estado concreto (producción casi
vacía), no un patrón a repetir — ver el aviso en `.claude/agents/dead-code-pruner.md` y el punto 12 de la
skill `db-schema`. Fundir un cambio dentro del baseline (ADR 0018) es una **segunda** excepción con la
misma fecha de caducidad: deja de ser posible en cuanto producción tenga usuarios reales.
