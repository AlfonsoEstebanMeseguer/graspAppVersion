-- Completa la reconciliación de un entorno que se quedó en el historial PRE-squash.
--
-- ===== Qué se midió, el 2026-08-23, contra producción =====
--
-- `supabase_migrations.schema_migrations` en producción se detenía en 20260813090000: las tres
-- migraciones del baseline (20260816120000/1/2) y 20260822180000 nunca se desplegaron. El squash
-- del ADR 0017 se llevó por delante 20260816090000 —la que cerró H-S-01— antes de que llegara a
-- producción, así que el agujero seguía abierto ALLÍ mientras el repositorio, CLAUDE.md,
-- docs/db-schema.md y la skill rls-security afirmaban las cuatro que estaba cerrado.
--
-- Estado real de producción en ese momento, comprobado contra los catálogos del sistema y no
-- deducido leyendo migraciones (que es justo lo que CLAUDE.md prohíbe):
--
--   * `public.profiles.phone_number` existía, con `profiles_phone_number_idx` encima.
--   * `authenticated` tenía SELECT sobre esa columna (grant de TABLA) y UPDATE (grant de columna).
--   * 3 perfiles, 2 con teléfono guardado.
--
-- Es H-S-01 vivo: `GET /rest/v1/profiles?select=display_name,phone_number` con cualquier JWT
-- volcaba la base entera, y el índice daba el oráculo inverso «¿este número está en Grasp?». En una
-- app de apoyo en salud mental eso es doxing. El detalle completo del hallazgo y el razonamiento de
-- por qué se BORRA en vez de moverse a `profiles_private` (Art. 5.1.c: a un dato que no lee nadie no
-- se le busca mejor escondite) están en la migración original, que sigue en el historial de git:
--
--   git show 482ff38^:apps/backend/supabase/migrations/20260816090000_drop_phone_number_and_harden_signup.sql
--
-- ===== Por qué esta migración existe y no basta con re-ejecutar el baseline =====
--
-- El baseline es idempotente A PROPÓSITO (ADR 0017) y al ejecutarse sobre producción arregla CINCO
-- de las seis divergencias medidas: el `do $$` que sanea `display_name`, el `set not null`,
-- `profiles_display_name_length_chk`, `profiles_private_gender_chk` y el `handle_new_user` validado
-- del ADR 0018. Lo que NO puede hacer es esta: su `create table if not exists public.profiles (…)`
-- es un no-op sobre una tabla que ya existe, así que **una columna sobrante sobrevive**. No hay un
-- solo `drop column` en todo `migrations/`.
--
-- Ésa es la lección general, y vale para cualquier squash futuro: **un baseline idempotente
-- reconstruye lo que debe existir, nunca retira lo que no debe.** Las partes destructivas de las
-- migraciones que sustituye se pierden con ellas, y no lo delata nada.
--
-- ===== No-op donde el esquema ya es correcto =====
--
-- Sobre cualquier entorno construido desde el baseline (`supabase db reset`, rama de preview,
-- CI) esto no cambia nada: `drop … if exists` sobre lo que no existe, y el revoke+grant reconcede
-- exactamente lo que ya había. Se queda en el repositorio como registro de que producción divergió
-- y de cómo se cerró.

-- ---------------------------------------------------------------------------------------------
-- 0) Guarda: falla CERRADO si el baseline no se ha ejecutado antes.
-- ---------------------------------------------------------------------------------------------
-- Esta migración cubre 1 de las 6 divergencias; las otras 5 las trae el baseline. Si alguien
-- reconcilia el historial marcando el baseline como `applied` SIN ejecutarlo —el Camino B que la
-- enmienda del ADR 0017 prohíbe— y luego aplica solo ésta, el entorno quedaría a medias: sin
-- teléfono (bien) pero sin la validación del alta ni el `not null` de `display_name` (mal), y nada
-- lo diría. La dependencia se comprueba, no se documenta.
do $$
begin
  if not exists (
    select 1 from pg_constraint
     where conrelid = 'public.profiles'::regclass
       and conname  = 'profiles_display_name_length_chk'
  ) then
    raise exception
      'Falta profiles_display_name_length_chk: el baseline 20260816120000 no se ha EJECUTADO en '
      'este entorno. Aplícalo antes (supabase db push). Ver ADR 0017, enmienda del 2026-08-17: el '
      'Camino B (marcar como applied sin ejecutar) está prohibido.'
      using errcode = 'raise_exception';
  end if;

  if exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'profiles'
       and column_name = 'display_name' and is_nullable = 'YES'
  ) then
    raise exception
      'public.profiles.display_name sigue siendo nullable: el baseline 20260816120000 no se ha '
      'EJECUTADO en este entorno (ADR 0018).'
      using errcode = 'raise_exception';
  end if;
end $$;

-- ---------------------------------------------------------------------------------------------
-- 1) H-S-01 — fuera la columna y su índice.
-- ---------------------------------------------------------------------------------------------
-- El índice es la mitad del daño: sin él sigue habiendo fuga, pero no oráculo inverso. Se borra
-- explícitamente antes que la columna para dejarlo escrito, aunque el `drop column` se lo llevaría.
--
-- IRREVERSIBLE: los teléfonos guardados se pierden. Es deliberado y está aceptado por escrito en el
-- ADR 0015. El ROLLBACK de abajo recrea la columna, nunca los datos.
drop index if exists public.profiles_phone_number_idx;

alter table public.profiles drop column if exists phone_number;

-- ---------------------------------------------------------------------------------------------
-- 2) Grants: explícitos, no deducidos.
-- ---------------------------------------------------------------------------------------------
-- Los grants de columna sobre una columna que ya no existe desaparecen solos, así que esto es
-- redundante en cuanto al efecto. Se escribe igualmente porque el estado de los grants NO se deduce
-- leyendo migraciones (CLAUDE.md, punto 11 de rls-security): la lista completa de lo que
-- `authenticated` puede escribir en `profiles` tiene que estar en un sitio y ser legible de un
-- vistazo. `anon` se nombra aparte porque un `revoke … from authenticated` NO le alcanza, y ésa es
-- justo la mitad que se olvidó una vez en este repositorio (20260809120000).
revoke update on public.profiles from authenticated;
revoke update on public.profiles from anon;
grant update (display_name, language) on public.profiles to authenticated;

-- ---------------------------------------------------------------------------------------------
-- 3) Verificación posterior (ejecutar a mano tras aplicar; no la hace la migración).
-- ---------------------------------------------------------------------------------------------
--   select column_name from information_schema.columns
--    where table_schema='public' and table_name='profiles' and column_name='phone_number';
--   -- 0 filas.
--
--   select grantee, privilege_type, string_agg(column_name, ', ' order by column_name)
--     from information_schema.column_privileges
--    where table_schema='public' and table_name='profiles' and grantee in ('anon','authenticated')
--    group by grantee, privilege_type order by 1, 2;
--   -- authenticated | UPDATE | display_name, language     <- y nada más
--   -- anon          | (sin filas)

-- ROLLBACK:
-- Recrea la estructura, NO los datos: los teléfonos borrados no vuelven.
-- alter table public.profiles add column if not exists phone_number text;
-- create index if not exists profiles_phone_number_idx on public.profiles (phone_number);
-- revoke update on public.profiles from authenticated;
-- grant update (display_name, language, phone_number) on public.profiles to authenticated;
