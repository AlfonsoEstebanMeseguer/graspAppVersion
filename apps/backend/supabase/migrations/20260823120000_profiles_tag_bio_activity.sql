-- =================================================================================================
-- Fase 4 · Tarea 1 — `profiles.tag`, `profiles.bio` y el latido de actividad.
--
-- Plan: docs/superpowers/plans/2026-08-23-contactos-y-mensajeria.md (Tarea 1)
-- Spec: docs/spec-contactos-mensajes-conectar.md (§6.2 el tag, §6.4 la bio, RN-11, RN-30, RN-32)
--
-- Tres cosas que esta migración deja establecidas y que NO son detalles de implementación:
--
--   1) `tag` NO lleva `grant update` para `authenticated`, y no lo llevará nunca. Ésa es LA
--      garantía de que el usuario no elige su tag (§1: "inmutable" = no lo elige), no una
--      comprobación dentro de un endpoint que alguien pueda olvidar mañana. Lo acuña siempre el
--      servidor; lo rota `profile-tag-rotate` (Tarea 7) con service_role.
--
--   2) `last_seen_at` va en `profiles_private`, NO en `profiles`. `grant select on public.profiles`
--      es de TABLA: cualquier columna que se añada allí queda legible por todo usuario registrado
--      (punto 9b de rls-security — así estuvo expuesto el teléfono). Una marca de última conexión
--      exacta y pública es una herramienta de acecho en una app de salud mental. RN-30 solo
--      necesita un booleano, y lo calcula el RPC `activity_status` de la Tarea 4.
--
--   3) El acuñado se engancha en `handle_new_user` porque es el ÚNICO camino de alta (punto 4d de
--      db-schema: la validación vive en el camino de escritura, no en el de edición).
-- =================================================================================================

-- =================================================================================================
-- 1) COLUMNAS NUEVAS DE `public.profiles`
-- =================================================================================================

-- Identificador público tecleable: `alfon#K7M2QX9F`. Según §6.2 es la ÚNICA forma de encontrar a
-- alguien a propósito, así que se teclea a mano en un móvil — de ahí el alfabeto de `mint_tag_suffix`.
-- Nace nullable y se rellena más abajo; el `set not null` va DESPUÉS del backfill (paso 4 del plan).
alter table public.profiles add column if not exists tag text;

-- Biografía del §6.4, truncada a 2 líneas en la tarjeta de Conectar. La escribe el usuario
-- (está en el `grant update` de abajo), a diferencia de `tag`.
alter table public.profiles add column if not exists bio text;

comment on column public.profiles.tag is
  'Identificador público tecleable (RN-11, §6.2), formato `local#SUFIJO` — ver `mint_user_tag`. '
  'INMUTABLE EN EL SENTIDO DE LA SPEC: el usuario no lo elige. La garantía es estructural — esta '
  'columna NO está en el `grant update` de `authenticated` y no debe añadirse nunca. La rotación '
  '(1 cada 24 h) es `profile-tag-rotate` con service_role, contra `profiles_private.tag_rotated_at`.';

comment on column public.profiles.bio is
  'Biografía pública del §6.4. Editable por el usuario (grant de columna). 1-160 caracteres tras '
  '`btrim`, o NULL; ver `profiles_bio_length_chk`.';

-- `bio is null or ...` es intencional y aquí SÍ significa algo, a diferencia del antipatrón del
-- punto 4e de db-schema: la bio es opcional de verdad, así que la ausencia es un estado válido y
-- lo que se acota es el CONTENIDO. El `btrim` es lo que impide que '   ' cuente como biografía:
-- `char_length('   ')` es 3, así que sin él la constraint aceptaría espacios.
alter table public.profiles drop constraint if exists profiles_bio_length_chk;
alter table public.profiles
  add constraint profiles_bio_length_chk
  check (bio is null or char_length(btrim(bio)) between 1 and 160);

-- =================================================================================================
-- 2) ACUÑADO DEL TAG
-- =================================================================================================

-- Alfabeto Crockford base32: sin I, L, O ni U. El tag se teclea A MANO en un móvil (RN-11 es la
-- única forma de encontrar a alguien), así que un 0 confundible con una O es un fallo de diseño,
-- no un detalle; sin U no sale ninguna palabra malsonante por azar. 256 % 32 = 0, así que el
-- módulo sobre un byte es uniforme y no hay sesgo hacia los primeros símbolos.
-- 32^8 ≈ 1,1 x 10^12 combinaciones por parte local.
--
-- `order by i` no está en el plan y se añade a propósito: sin él el orden de agregación lo decide
-- el planificador. No cambia la aleatoriedad (los bytes ya son aleatorios), pero hace que la
-- salida sea una función determinista de los bytes, que es lo que se quiere de un acuñador.
-- `security invoker` (el defecto) A PROPÓSITO, y no es un olvido frente a `mint_user_tag`: no lee
-- ninguna tabla, así que no tiene RLS que saltarse. Su único llamante es `mint_user_tag`, que sí es
-- `security definer` y por tanto la ejecuta ya como `postgres`, su dueño. Ascenderla sería ampliar
-- privilegios para resolver un problema que no existe — punto 14 de rls-security.
create or replace function public.mint_tag_suffix()
returns text
language sql
volatile
set search_path = ''
as $$
  select string_agg(
           substr('0123456789ABCDEFGHJKMNPQRSTVWXYZ', 1 + (get_byte(b, i) % 32), 1),
           '' order by i)
    from (select extensions.gen_random_bytes(8) as b) s,
         generate_series(0, 7) as i;
$$;

-- Acuña un tag libre a partir del nombre visible.
--
-- Parte local: `normalize(..., NFD)` separa la tilde de la letra y el `regexp_replace` se la lleva
-- junto con todo lo que no sea alfanumérico ASCII, en una sola pasada. Es el mismo truco que
-- `toSlug` en `_shared/validation.ts`, así que el SQL y su espejo de Deno comparten una idea en
-- vez de tener dos. Verificado contra esta misma base:
--   'Alfonso Estebán' → alfonsoesteb · 'María José' → mariajose · 'Begoña' → begona
--   'Дмитрий' → grasp · '   ' → grasp · '🌈🌈' → grasp · 'Ana-Maria O''Neill' → anamariaonei
-- Se descartó `unaccent` (no está instalada) y `translate` con una pareja de 48 caracteres
-- (frágil y solo cubre el español).
--
-- El fallback 'grasp' no es decorativo: sin él, un nombre entero en cirílico o en emoji acuñaría
-- un tag que empieza por '#'.
--
-- SOBRE LA UNICIDAD, y conviene leerlo antes de "simplificar" el bucle: la autoridad es el índice
-- único `profiles_tag_key`, no este `not exists`. Entre la comprobación y el INSERT del llamante
-- hay una ventana en la que otra transacción puede acuñar el mismo tag; con 1,1 x 10^12
-- combinaciones eso no ocurre en la práctica, y si ocurriese el índice lo rechaza (un alta fallida,
-- nunca dos usuarios con el mismo tag). El bucle existe para el caso realista —que el tag ya esté
-- ocupado y haya que probar otro—, no para cerrar esa ventana.
create or replace function public.mint_user_tag(p_display_name text)
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_local text;
  v_tag   text;
begin
  v_local := coalesce(
    nullif(
      left(lower(regexp_replace(normalize(coalesce(p_display_name, ''), NFD), '[^a-zA-Z0-9]', '', 'g')), 12),
      ''),
    'grasp');

  for _ in 1..5 loop
    v_tag := v_local || '#' || public.mint_tag_suffix();
    if not exists (select 1 from public.profiles p where p.tag = v_tag) then
      return v_tag;
    end if;
  end loop;

  raise exception 'no se pudo acunar un tag libre para % tras 5 intentos', v_local
    using errcode = 'unique_violation';
end;
$$;

-- Punto 11 de db-schema: CUALQUIER función de `public` la expone PostgREST como
-- `POST /rest/v1/rpc/<nombre>` ejecutable por anon/authenticated salvo que se revoque. Las dos son
-- `security definer`, así que dejarlas expuestas sería regalar un acuñador de tags a internet.
-- El `revoke ... from public` alcanza también a service_role (no es superusuario), por eso
-- `mint_user_tag` lleva después un `grant` explícito: lo llama `profile-tag-rotate` (Tarea 7).
-- `mint_tag_suffix` NO lo lleva: solo la llama `mint_user_tag`, que al ser `security definer`
-- propiedad de `postgres` la ejecuta con los privilegios del dueño.
revoke execute on function public.mint_tag_suffix() from public, anon, authenticated;
revoke execute on function public.mint_user_tag(text) from public, anon, authenticated;
grant  execute on function public.mint_user_tag(text) to service_role;

-- =================================================================================================
-- 3) BACKFILL → ÍNDICE ÚNICO → NOT NULL, EN ESTE ORDEN
--    Al revés, una base con filas revienta: el índice único sobre varias filas con `tag is null`
--    sí pasaría (los NULL no colisionan en un btree), pero el `set not null` no.
-- =================================================================================================

do $$
declare
  r record;
begin
  for r in select user_id, display_name from public.profiles where tag is null loop
    update public.profiles
       set tag = public.mint_user_tag(r.display_name)
     where user_id = r.user_id;
  end loop;
end $$;

create unique index if not exists profiles_tag_key on public.profiles (tag);

alter table public.profiles alter column tag set not null;

-- =================================================================================================
-- 4) `handle_new_user` — EL ÚNICO CAMINO DE ALTA
--
-- Se reproduce entero (`create or replace` no permite parchear un trozo) conservando literalmente
-- la validación del ADR 0018. El ÚNICO cambio respecto de 20260816120000 es el `tag` del INSERT.
-- Los comentarios de dentro del `$$ ... $$` son parte del código fuente que pg_dump reproduce, así
-- que se conservan tal cual para que la comparación entre entornos siga siendo legible.
-- =================================================================================================

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  meta jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
  -- `btrim` antes del `nullif`: así '   ' se convierte en NULL y cae en el rechazo de abajo,
  -- y el nombre llega a `profiles` ya recortado, igual que lo deja `profile-update`.
  v_display_name text := nullif(btrim(meta->>'display_name'), '');
  v_gender text := nullif(meta->>'gender', '');
  v_birth_date_raw text := nullif(meta->>'birth_date', '');
  v_birth_date date;
begin
  -- `raw_user_meta_data` lo elige QUIEN LLAMA, no la app: la clave publicable va embebida en el
  -- binario, así que cualquiera puede mandar el `data` que quiera al endpoint de alta de GoTrue.
  -- Todo lo que salga de aquí se trata como entrada hostil.

  -- Obligatorio desde el 2026-08-17 (ADR 0018). Sin esto el alta creaba perfiles sin nombre:
  -- la constraint de longitud los dejaba pasar por ser NULL. Se rechaza aquí, y no solo en la
  -- constraint, para que el error diga QUÉ campo falta en vez de citar un nombre de constraint.
  if v_display_name is null then
    raise exception 'display_name es obligatorio'
      using errcode = 'check_violation';
  end if;

  if char_length(v_display_name) > 60 then
    raise exception 'display_name excede 60 caracteres'
      using errcode = 'check_violation';
  end if;

  if v_gender is not null and v_gender not in ('hombre', 'mujer', 'otro') then
    raise exception 'gender no es un valor admitido'
      using errcode = 'check_violation';
  end if;

  if v_birth_date_raw is not null then
    -- Se parsea con manejo de error en vez de dejar que el cast reviente: un `::date` sobre basura
    -- lanzaba `invalid_datetime_format` DENTRO del trigger y tumbaba el INSERT en auth.users, así
    -- que el alta devolvía un 500 opaco en lugar de decir qué campo estaba mal.
    begin
      v_birth_date := v_birth_date_raw::date;
    exception when others then
      raise exception 'birth_date debe tener formato YYYY-MM-DD'
        using errcode = 'check_violation';
    end;

    -- Art. 8 RGPD: por debajo de 13 años no hay consentimiento válido. Es la barrera que faltaba en
    -- el único camino por el que se crean cuentas.
    if v_birth_date > current_date - interval '13 years' then
      raise exception 'birth_date implica una edad menor de 13 anios'
        using errcode = 'check_violation';
    end if;

    if v_birth_date < current_date - interval '120 years' then
      raise exception 'birth_date implica una edad fuera de rango'
        using errcode = 'check_violation';
    end if;
  end if;

  -- El tag se acuña AQUÍ porque éste es el único camino de alta (punto 4d de db-schema). Si se
  -- dejara para un endpoint posterior existirían perfiles sin tag, y `tag` es `not null`.
  insert into public.profiles (user_id, display_name, tag)
  values (new.id, v_display_name, public.mint_user_tag(v_display_name))
  on conflict (user_id) do nothing;

  insert into public.profiles_private (user_id, birth_date, gender)
  values (new.id, v_birth_date, v_gender)
  on conflict (user_id) do nothing;

  return new;
end;
$$;

-- Se repite tras cada `create or replace` aunque éste preserve los grants existentes, para que
-- quien lea esta migración suelta no tenga que ir a comprobarlo. Origen: 20260808000000.
revoke execute on function public.handle_new_user() from public, anon, authenticated;

-- =================================================================================================
-- 5) `public.profiles_private` — EL LATIDO DE ACTIVIDAD
-- =================================================================================================

alter table public.profiles_private add column if not exists last_seen_at timestamptz;
alter table public.profiles_private add column if not exists hide_activity_status boolean not null default false;
alter table public.profiles_private add column if not exists tag_rotated_at timestamptz;

comment on column public.profiles_private.last_seen_at is
  'Último latido del usuario (RN-30). VIVE AQUÍ Y NO EN `public.profiles` A PROPÓSITO: '
  '`grant select on public.profiles` es de TABLA, así que cualquier columna añadida allí es '
  'legible por TODO usuario registrado (punto 9b de rls-security), y una marca de última conexión '
  'exacta y pública es una herramienta de acecho en una app de salud mental. Aquí la policy '
  '`profiles_private_read_own` la cierra al propio usuario. RN-30 solo necesita un BOOLEANO, y lo '
  'deriva el RPC `activity_status` (Tarea 4), que nunca devuelve esta marca de tiempo. '
  'No se concede en ningún `grant update`: la escribe el RPC `touch_last_seen` con service_role.';

comment on column public.profiles_private.hide_activity_status is
  'RN-32: el usuario oculta su punto de actividad. Es RECÍPROCO — quien lo activa tampoco ve el de '
  'los demás, y esa reciprocidad la impone `activity_status` (Tarea 4), no el cliente. Es la única '
  'de las tres columnas de este bloque que el usuario escribe (ver grants).';

comment on column public.profiles_private.tag_rotated_at is
  'Momento de la última rotación de `profiles.tag`. Sostiene el tope de 1 cada 24 h de '
  '`profile-tag-rotate` (Tarea 7), que responde 422 con el instante de recuperación (RN-21). '
  'No se concede en ningún `grant update`: si el cliente pudiera escribirla, el tope no existiría.';

-- =================================================================================================
-- 6) GRANTS — LOS TRES ROLES, EXPLÍCITOS (puntos 11 y 12 de rls-security)
--    El estado real NO se deduce leyendo esta migración; la verificación contra
--    `information_schema.column_privileges` va al final del fichero.
-- =================================================================================================

-- --- anon: nada, ni antes ni ahora. Se nombra aparte porque un `revoke ... from authenticated`
--     NO le alcanza, y ésa es justo la mitad que se olvidó una vez aquí (20260809120000).
revoke update on public.profiles         from anon;
revoke update on public.profiles_private from anon;

-- --- authenticated: reset y reconstrucción explícita de la lista COMPLETA. Reemplaza la línea de
--     20260823110000 (`display_name, language`).
--
--     `tag` NO ENTRA, y no es un olvido: es el invariante nº 1 de esta migración. `bio` sí, porque
--     es texto del usuario. `photo_path`/`preset_avatar` los escribe `profile-avatar-set` con
--     service_role; `level`, `xp`, `vip_status` y los contadores son entitlements y CLAUDE.md
--     prohíbe que el cliente los toque.
revoke update on public.profiles from authenticated;
grant update (display_name, language, bio) on public.profiles to authenticated;

--     De las tres columnas nuevas de `profiles_private` solo `hide_activity_status` es del usuario:
--     es una PREFERENCIA. `last_seen_at` la escribe `touch_last_seen` (Tarea 4) y `tag_rotated_at`
--     la escribe `profile-tag-rotate` (Tarea 7): si el cliente pudiera escribirlas, podría fingir
--     actividad permanente y saltarse el tope de rotación.
revoke update on public.profiles_private from authenticated;
grant update (birth_date, gender, country, hide_activity_status) on public.profiles_private to authenticated;

-- --- service_role: no necesita ningún grant nuevo. `20260816120000` ya le concedió
--     `select, update` de TABLA sobre las dos, y un grant de tabla cubre las columnas que se le
--     añadan después (a service_role no se le acota por columna — punto 12 de rls-security: el
--     control de columna existe para que el CLIENTE no se autoconceda estado de backend, y
--     service_role nunca viaja al cliente). Se deja escrito para que nadie lo "arregle".

-- --- `select`: `profiles` y `profiles_private` ya tienen `grant select` de TABLA para
--     `authenticated`, así que `tag` y `bio` quedan legibles por cualquier usuario registrado
--     —que es lo que se quiere: son públicas— y `last_seen_at`, `hide_activity_status` y
--     `tag_rotated_at` quedan cerradas por la policy `profiles_private_read_own`, que solo deja
--     ver la fila propia. Ésa es la razón de que `last_seen_at` esté en esta tabla y no en la otra.

-- =================================================================================================
-- VERIFICACIÓN POSTERIOR (a mano tras aplicar; la migración no la hace)
-- =================================================================================================
--   select grantee, privilege_type, string_agg(column_name, ', ' order by column_name)
--     from information_schema.column_privileges
--    where table_schema = 'public' and table_name in ('profiles', 'profiles_private')
--      and grantee in ('anon', 'authenticated', 'service_role')
--    group by grantee, privilege_type order by 1, 2;
--   -- authenticated | UPDATE | bio, display_name, language          <- sin `tag`
--   -- authenticated | UPDATE | birth_date, country, gender, hide_activity_status
--   --                                                               <- sin `last_seen_at` ni `tag_rotated_at`
--   -- anon          | (sin filas)
--
--   select count(*) as sin_tag from public.profiles where tag is null;   -- 0
--   select count(*) filter (where tag !~ '^[a-z0-9]{1,12}#[0-9A-HJKMNP-TV-Z]{8}$') from public.profiles;  -- 0

-- =================================================================================================
-- ROLLBACK:
-- =================================================================================================
-- -- Devuelve `handle_new_user` a su cuerpo de 20260816120000 (sin `tag` en el INSERT) ANTES de
-- -- borrar la columna, o el trigger de alta falla con "column tag does not exist".
-- revoke update on public.profiles_private from authenticated;
-- grant update (birth_date, gender, country) on public.profiles_private to authenticated;
-- revoke update on public.profiles from authenticated;
-- grant update (display_name, language) on public.profiles to authenticated;
-- alter table public.profiles_private drop column if exists tag_rotated_at;
-- alter table public.profiles_private drop column if exists hide_activity_status;
-- alter table public.profiles_private drop column if exists last_seen_at;
-- alter table public.profiles drop constraint if exists profiles_bio_length_chk;
-- alter table public.profiles alter column tag drop not null;
-- drop index if exists public.profiles_tag_key;
-- alter table public.profiles drop column if exists bio;
-- alter table public.profiles drop column if exists tag;
-- drop function if exists public.mint_user_tag(text);
-- drop function if exists public.mint_tag_suffix();
