-- =================================================================================================
-- El perfil ajeno (`RN-38`, §6.2) — Fase 4, Tarea 24, paso 5.
--
-- QUÉ RESUELVE
--   La pantalla de perfil de OTRA persona tiene tres puertas de entrada (la tarjeta de Conectar,
--   la ficha del tag y la cabecera de la conversación) y tiene que enseñar lo mismo desde las
--   tres. Todo lo que pide el §6.2 era ya legible por `authenticated` —`display_name`, `tag`,
--   `bio`, `level` y las insignias— MENOS la edad.
--
-- POR QUÉ LA EDAD NO LO ERA, Y POR QUÉ NO BASTABA CON ABRIR UNA POLICY
--   La edad NO EXISTÍA ALMACENADA. `profiles_private.age` era una columna `int` que **no escribía
--   nadie** y que estaba a `NULL` en todas las filas; la edad real la derivaba `connect-feed` de
--   `profiles_private.birth_date`, en Deno, y su propio README lo dejaba escrito. Esta migración
--   la borra: a un dato que no lee nadie no se le busca mejor escondite (CLAUDE.md, Art. 5.1.c),
--   y dejarla conviviendo con la `age` de la vista daría DOS cosas con el mismo nombre de las que
--   la de la tabla es la que miente.
--
--   Y la vía corta —añadir a `profiles_private` una policy de lectura pública— es justo la que no
--   se puede tomar: **RLS es por fila, no por columna**. Una policy con `qual = true` sobre esa
--   tabla abriría de golpe `primary_category_id`, `secondary_categories`, `gender` y `birth_date`,
--   que son el catálogo de salud mental y el ADR 0020 entero. La frontera del Art. 9 pasa por
--   aquí.
--
-- LA DECISIÓN: UNA VISTA QUE ENUMERA
--   `public.public_profiles` lista **una a una** las columnas públicas y calcula `age` al vuelo
--   desde `birth_date`. Tres propiedades que se ganan por la forma y no por disciplina:
--
--     1. `birth_date` NO SALE. Sale el número de años; la fecha se queda dentro.
--     2. La edad no se desfasa nunca. Se calcula al leer, así que es correcta el día del
--        cumpleaños sin trigger, sin cron y sin columna que mantener. Una `profiles.age`
--        almacenada mentiría desde el día siguiente a cada cumpleaños.
--     3. Enumerar es un `grant` por columna POR CONSTRUCCIÓN: una columna nueva en `profiles` no
--        se cuela sola en esta respuesta, que es exactamente el fallo que `SupabaseFollowRepository`
--        evita a mano al no usar `select *`. Aquí lo impone la base.
--
-- LA VISTA ES LA FRONTERA DE AUTORIZACIÓN, Y ESO ES DELIBERADO
--   Va con `security_invoker = false` **explícito** y no por defecto: corre con los privilegios de
--   su dueño, así que se salta la RLS de `profiles_private` — que es la única forma de leer el
--   `birth_date` de otra persona. Consecuencia que hay que tener presente al tocarla: **lo único
--   que decide qué se ve de esta tabla es la lista de columnas de abajo.** Añadir una columna a
--   ese `select` no es un detalle de conveniencia, es conceder un permiso.
--
--   No amplía QUÉ FILAS se ven: `profiles_read_public` ya es `qual = true`, así que la lista de
--   perfiles era enumerable desde el Bloque 1. Lo que esta vista añade es una columna, `age`, y
--   sólo para `authenticated`.
--
-- Decidido por el usuario en sesión el 2026-08-27, cambiando la decisión anterior de la misma
-- sesión (quitar la edad del perfil ajeno). Ver `docs/decisions/0026-la-edad-es-publica.md`.
--
-- ROLLBACK: al final del fichero.
-- =================================================================================================

-- =================================================================================================
-- 1) LA COLUMNA MUERTA
--    `profiles_private.age` no la escribía ningún camino: ni el trigger de alta, ni
--    `profile-update` (que sólo escribe `birth_date`), ni ninguna Edge Function. Comprobado con
--    `grep` sobre `apps/backend` y `apps/mobile` antes de borrarla: la única `age` viva es la que
--    `connect-feed` DERIVA de `birth_date`, y el mapper de Flutter hace lo mismo con la propia.
-- =================================================================================================
alter table public.profiles_private drop column if exists age;

-- =================================================================================================
-- 2) LA EDAD, DERIVADA — espejo exacto de `ageFrom()` en `connect-feed/index.ts`
--
--    La autoridad del cálculo pasa a ser ESTA función, y `connect-feed` sigue teniendo la suya en
--    Deno porque puntúa con ella sin pasar por la vista. Que las dos coincidan importa: la tarjeta
--    de Conectar y el perfil que se abre desde esa misma tarjeta enseñan el mismo número, y una
--    diferencia de un año sería un fallo visible y difícil de explicar.
--
--    Por eso se fija UTC en vez de `current_date`: `current_date` depende del `TimeZone` de la
--    sesión, y PostgREST no garantiza cuál es. Deno calcula en UTC (`getUTCFullYear`), así que
--    aquí también, o los dos números divergirían durante unas horas al día.
--
--    El descarte de `< 0` y `>= 130` es el mismo de allí: una fecha imposible produce `null`, no
--    un número absurdo pintado en una pantalla.
-- =================================================================================================
create or replace function public.age_in_years(p_birth_date date)
returns int
language sql
stable
set search_path = ''
as $$
  select case when anios >= 0 and anios < 130 then anios end
    from (
      select extract(
               year from pg_catalog.age(
                 (pg_catalog.timezone('UTC', pg_catalog.now()))::date,
                 p_birth_date
               )
             )::int as anios
    ) s;
$$;

comment on function public.age_in_years(date) is
  'Años cumplidos en UTC, o NULL si la fecha es nula o imposible. Espejo de ageFrom() en '
  'connect-feed/index.ts: los dos números se pintan en pantallas contiguas y tienen que coincidir.';

-- =================================================================================================
-- 3) LA VISTA
--
--    LO QUE NO ESTÁ AQUÍ, Y POR QUÉ — la lista negra importa tanto como la blanca:
--
--      `birth_date`            la fecha exacta identifica mucho más que la edad. Sale el derivado.
--      `gender`, `country`     nadie los pide en el §6.2. No se publica lo que no se pinta.
--      `primary_category_id`   ART. 9 RGPD. Es el catálogo de salud mental (ADR 0020). Jamás.
--      `secondary_categories`  ídem.
--      `last_seen_at`          `RN-30` se responde con el RPC `activity_status`, que devuelve un
--                              BOOLEANO y nunca una marca de tiempo, y que aplica la reciprocidad
--                              de `RN-32` por dentro. Una marca aquí desharía esa migración entera.
--      `hide_activity_status`  es un ajuste de privacidad: quien lo activa no quiere que se sepa.
--      `xp`                    el §6.2 pide el NIVEL. El xp es el detalle de progreso propio.
--      `vip_status`,           entitlements y estado de backend. No son parte de un perfil ajeno.
--      `reputation_score`
-- =================================================================================================
drop view if exists public.public_profiles;

create view public.public_profiles
with (security_invoker = false) as
select
  p.user_id,
  p.display_name,
  p.tag,
  p.bio,
  p.preset_avatar,
  p.photo_path,
  p.level,
  p.streak_days,
  p.time_helping_seconds,
  p.followers_count,
  p.following_count,
  public.age_in_years(pp.birth_date) as age
from public.profiles p
left join public.profiles_private pp on pp.user_id = p.user_id;

comment on view public.public_profiles is
  'El perfil de OTRA persona (RN-38, §6.2). security_invoker = false a propósito: es la única '
  'forma de derivar la edad de profiles_private.birth_date sin abrir esa tabla entera. La lista '
  'de columnas ES la autorización — añadir una es conceder un permiso, no un detalle.';

-- =================================================================================================
-- 4) GRANTS — LOS TRES ROLES, EXPLÍCITOS (puntos 11 y 12 de `rls-security`)
--
--    El `revoke ... from public` de la primera línea NO es ceremonia: los default privileges son
--    estado del entorno y no del repositorio, y divergen entre entornos (puntos 13-14). Un entorno
--    más permisivo que el local ESCONDERÍA un grant olvidado en vez de delatarlo, así que se parte
--    de cero y se concede a mano.
--
--    Una vista sobre un JOIN no es auto-actualizable en Postgres, así que no hay `insert`/`update`
--    que revocar de verdad — pero se revoca igual: la propiedad que protege el dato no puede
--    depender de un detalle del planificador.
-- =================================================================================================
revoke all on public.public_profiles from public;
revoke all on public.public_profiles from anon;
revoke all on public.public_profiles from authenticated;

-- --- anon: NADA. Se nombra arriba y no se le concede aquí. El perfil ajeno se mira desde dentro
--     de la app, con sesión: sin esto, la edad de todo el mundo sería legible con la anon key, que
--     va embebida en el binario y por tanto es pública de hecho.
grant select on public.public_profiles to authenticated;
grant select on public.public_profiles to service_role;

-- --- La función: por defecto `execute` va a `public`, así que se revoca y se concede a mano por
--     lo mismo de arriba. La vista corre como su dueño, pero se conceden los dos roles para que
--     un `select public.age_in_years(...)` desde una Edge Function tampoco dependa del default.
revoke execute on function public.age_in_years(date) from public;
revoke execute on function public.age_in_years(date) from anon;
grant execute on function public.age_in_years(date) to authenticated;
grant execute on function public.age_in_years(date) to service_role;

-- =================================================================================================
-- VERIFICACIÓN POSTERIOR (a mano tras aplicar; la migración no la hace). El estado real NO se
-- deduce leyendo esta migración — `information_schema` es la única autoridad (punto 11).
-- =================================================================================================
--   select grantee, privilege_type, string_agg(column_name, ', ' order by column_name)
--     from information_schema.column_privileges
--    where table_schema = 'public' and table_name = 'public_profiles'
--      and grantee in ('anon', 'authenticated', 'service_role')
--    group by grantee, privilege_type order by 1, 2;
--   -- authenticated | SELECT | age, bio, display_name, followers_count, following_count, level,
--   --                          photo_path, preset_avatar, streak_days, tag, time_helping_seconds,
--   --                          user_id
--   -- service_role  | SELECT | (las mismas)
--   -- anon          | (sin filas)
--
--   -- Y la que de verdad importa: que no se coló nada de lo prohibido.
--   select count(*) from information_schema.columns
--    where table_schema = 'public' and table_name = 'public_profiles'
--      and column_name in ('birth_date', 'gender', 'country', 'primary_category_id',
--                          'secondary_categories', 'last_seen_at', 'hide_activity_status',
--                          'xp', 'vip_status', 'reputation_score');   -- 0
--
--   select count(*) from information_schema.columns
--    where table_schema = 'public' and table_name = 'profiles_private' and column_name = 'age';  -- 0

-- =================================================================================================
-- ROLLBACK:
--
--   drop view if exists public.public_profiles;
--   drop function if exists public.age_in_years(date);
--   alter table public.profiles_private add column if not exists age int;
--   -- La columna vuelve VACÍA, que es exactamente como estaba: nadie la escribía.
-- =================================================================================================
