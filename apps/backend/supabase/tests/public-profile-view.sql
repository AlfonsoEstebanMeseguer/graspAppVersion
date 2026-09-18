-- Test de `public.public_profiles` (Fase 4, Tarea 24, paso 5) — el perfil ajeno.
--
-- LO QUE SE PRUEBA AQUÍ NO ES «LA VISTA DEVUELVE LO ESPERADO»
--   La vista corre con `security_invoker = false`, o sea que se salta la RLS de las tablas base.
--   Eso la convierte en la ÚNICA frontera de autorización de lo que publica, así que lo que estos
--   casos fijan es dónde está esa frontera:
--
--     1. Un usuario ve la edad de OTRO (caso 2) — sin esto la vista no serviría para nada, y es
--        el caso que la prueba puede perder si algún día alguien le pone `security_invoker = true`
--        «por seguridad»: `profiles_private_read_own` la dejaría a NULL en silencio.
--     2. `birth_date` y las categorías del Art. 9 NO están entre sus columnas (caso 3). Es el
--        ADR 0020 y es lo que separa esta migración de la vía corta que no se tomó.
--     3. `anon` no puede leerla (caso 4). La anon key va embebida en la app.
--     4. La edad coincide con la que calcula `connect-feed` en Deno (caso 5), incluido el día
--        del cumpleaños — que es el único día en que un cálculo mal hecho se nota.
--
-- CÓMO SE EJECUTA
--     docker exec -i supabase_db_backend psql -U postgres -d postgres \
--       -v ON_ERROR_STOP=1 < apps/backend/supabase/tests/public-profile-view.sql
--
-- Todo corre dentro de una transacción que termina en ROLLBACK: no deja rastro.
--
-- LOS DOS USUARIOS
--   A — quien mira. Nacida el 2000-03-15.
--   B — a quien se mira. Nacido el 1990-08-27 (hoy, si se ejecuta el día del aniversario).

begin;

-- =====================================================================================
-- Caso 0: alta de los dos
-- =====================================================================================
do $$
declare
  v_a uuid := 'aaaaaaaa-0024-0000-0000-00000000000a';
  v_b uuid := 'bbbbbbbb-0024-0000-0000-00000000000b';
begin
  insert into auth.users (id, email, raw_user_meta_data) values
    (v_a, 'a-pub@example.test', '{"display_name":"Ana"}'::jsonb),
    (v_b, 'b-pub@example.test', '{"display_name":"Bruno"}'::jsonb);

  update public.profiles_private set birth_date = date '2000-03-15' where user_id = v_a;
  update public.profiles_private set birth_date = date '1990-08-27' where user_id = v_b;

  update public.profiles set bio = 'Aquí para escuchar', level = 7 where user_id = v_b;

  raise notice 'Caso 0 OK: A y B dados de alta con fecha de nacimiento';
end $$;

-- =====================================================================================
-- Caso 1: la columna muerta ya no existe
--   `profiles_private.age` no la escribía nadie y estaba a NULL en todas las filas. Si vuelve,
--   habrá dos `age` y la de la tabla será la que miente.
-- =====================================================================================
do $$
declare
  v_existe int;
begin
  select count(*) into v_existe
    from information_schema.columns
   where table_schema = 'public' and table_name = 'profiles_private' and column_name = 'age';

  if v_existe <> 0 then
    raise exception 'Caso 1 FALLA: profiles_private.age sigue existiendo. Nadie la escribe: '
                    'a un dato que no lee nadie no se le busca mejor escondite, se borra.';
  end if;

  raise notice 'Caso 1 OK: profiles_private.age borrada';
end $$;

-- =====================================================================================
-- Caso 2: A ve la edad de B, y su nombre, tag, bio y nivel
--
--   ESTE ES EL CASO QUE JUSTIFICA `security_invoker = false`. Con `true`, la policy
--   `profiles_private_read_own` dejaría `age` a NULL para cualquiera que no seas tú, y la vista
--   pasaría todos los demás casos de este fichero sin quejarse: un NULL y una edad son el mismo
--   tipo. Por eso se afirma sobre el VALOR y no sobre «devuelve una fila».
-- =====================================================================================
do $$
declare
  v_age int;
  v_nombre text;
  v_bio text;
  v_level int;
  v_tag text;
begin
  set local role authenticated;
  set local request.jwt.claims = '{"sub":"aaaaaaaa-0024-0000-0000-00000000000a"}';

  select age, display_name, bio, level, tag
    into v_age, v_nombre, v_bio, v_level, v_tag
    from public.public_profiles
   where user_id = 'bbbbbbbb-0024-0000-0000-00000000000b';

  if v_age is null then
    raise exception 'Caso 2 FALLA: A no ve la edad de B. Con security_invoker = true la policy '
                    'profiles_private_read_own la deja a NULL y el perfil ajeno queda sin edad.';
  end if;
  if v_age <> extract(year from age((now() at time zone 'utc')::date, date '1990-08-27'))::int then
    raise exception 'Caso 2 FALLA: la edad de B es %, no la esperada', v_age;
  end if;
  if v_nombre <> 'Bruno' then raise exception 'Caso 2 FALLA: nombre %', v_nombre; end if;
  if v_bio <> 'Aquí para escuchar' then raise exception 'Caso 2 FALLA: bio %', v_bio; end if;
  if v_level <> 7 then raise exception 'Caso 2 FALLA: nivel %', v_level; end if;
  if v_tag is null then raise exception 'Caso 2 FALLA: sin tag'; end if;

  raise notice 'Caso 2 OK: A ve edad %, nombre, tag, bio y nivel de B', v_age;
end $$;

-- =====================================================================================
-- Caso 3: NI UNA COLUMNA DEL ART. 9, NI `birth_date`
--
--   La vía corta que no se tomó era una policy de lectura pública sobre `profiles_private`. RLS
--   es por fila, no por columna: eso habría abierto las dos columnas de categorías de golpe. Este
--   caso es el que se pone rojo si alguien vuelve a intentarlo por la vía de la vista.
-- =====================================================================================
do $$
declare
  v_prohibida text;
begin
  select string_agg(column_name, ', ' order by column_name) into v_prohibida
    from information_schema.columns
   where table_schema = 'public' and table_name = 'public_profiles'
     and column_name in ('birth_date', 'gender', 'country', 'primary_category_id',
                         'secondary_categories', 'last_seen_at', 'hide_activity_status',
                         'xp', 'vip_status', 'reputation_score');

  if v_prohibida is not null then
    raise exception 'Caso 3 FALLA: public_profiles expone %. La lista de columnas de esa vista ES '
                    'la autorización (ADR 0020, RN-30, RN-32).', v_prohibida;
  end if;

  raise notice 'Caso 3 OK: la vista no expone birth_date, categorías, last_seen_at ni entitlements';
end $$;

-- =====================================================================================
-- Caso 4: `anon` no puede leerla
--   La anon key viaja embebida en el binario de la app, así que un grant a `anon` es un grant a
--   internet. Se comprueba contra `information_schema` y además intentándolo de verdad: el grant
--   podría venir de un default privilege del entorno y no de ninguna migración (puntos 13-14).
-- =====================================================================================
do $$
declare
  v_grants int;
begin
  -- `RESET ROLE` Y NO ES HIGIENE: `set local role` dura hasta el final de la TRANSACCIÓN, no del
  -- bloque, así que el `authenticated` del caso 2 seguía puesto aquí. E `information_schema`
  -- filtra por los privilegios del rol actual: como `authenticated` no ve los grants de `anon`,
  -- este caso contaba CERO pasara lo que pasara y decía «anon no tiene ningún privilegio» con el
  -- grant puesto. Se descubrió mutando la migración para conceder `select` a `anon`: el caso
  -- seguía en verde y sólo cayó el 4b. Un guardián que no puede fallar no guarda nada.
  reset role;

  select count(*) into v_grants
    from information_schema.table_privileges
   where table_schema = 'public' and table_name = 'public_profiles' and grantee = 'anon';

  if v_grants <> 0 then
    raise exception 'Caso 4 FALLA: anon tiene % privilegio(s) sobre public_profiles', v_grants;
  end if;

  raise notice 'Caso 4 OK: anon no tiene ningún privilegio sobre la vista';
end $$;

do $$
declare
  v_leyo int;
begin
  set local role anon;
  begin
    select count(*) into v_leyo from public.public_profiles;
    reset role;
    raise exception 'Caso 4b FALLA: anon leyó % filas de public_profiles', v_leyo;
  exception
    when insufficient_privilege then
      reset role;
      raise notice 'Caso 4b OK: anon recibe insufficient_privilege al leer la vista';
  end;
end $$;

-- =====================================================================================
-- Caso 5: el cálculo de la edad, incluido el día del cumpleaños
--
--   Es el único día en que un cálculo mal hecho se nota, y es el que separa `year - year` de la
--   resta correcta. Se prueban los tres días alrededor con una fecha fija, no con `now()`, para
--   que el test no dependa de cuándo se ejecute.
-- =====================================================================================
do $$
declare
  v_hoy date := (now() at time zone 'utc')::date;
begin
  -- Cumple hoy: años exactos.
  if public.age_in_years((v_hoy - interval '30 years')::date) <> 30 then
    raise exception 'Caso 5 FALLA: quien cumple 30 HOY no tiene 30 años, sino %',
      public.age_in_years((v_hoy - interval '30 years')::date);
  end if;

  -- Cumple mañana: todavía tiene 29.
  if public.age_in_years((v_hoy - interval '30 years' + interval '1 day')::date) <> 29 then
    raise exception 'Caso 5 FALLA: quien cumple 30 MAÑANA ya aparece con 30. Es el fallo de '
                    'restar los años sin mirar el día.';
  end if;

  -- Cumplió ayer: 30 recién estrenados.
  if public.age_in_years((v_hoy - interval '30 years' - interval '1 day')::date) <> 30 then
    raise exception 'Caso 5 FALLA: quien cumplió 30 AYER no tiene 30';
  end if;

  -- Nulo y fecha imposible: NULL, nunca un número absurdo en pantalla.
  if public.age_in_years(null) is not null then
    raise exception 'Caso 5 FALLA: sin fecha de nacimiento la edad no es NULL';
  end if;
  if public.age_in_years(date '1500-01-01') is not null then
    raise exception 'Caso 5 FALLA: una fecha imposible produce un número en vez de NULL';
  end if;

  raise notice 'Caso 5 OK: la edad se calcula bien el día antes, el día del cumpleaños y el de después';
end $$;

-- =====================================================================================
-- Caso 6: quien no tiene fecha de nacimiento aparece SIN EDAD, no fuera de la lista
--   El `left join` no es un detalle: con un `join` a secas, un perfil sin fila en
--   `profiles_private` desaparecería de la vista y su perfil ajeno daría «no existe».
-- =====================================================================================
do $$
declare
  v_c uuid := 'cccccccc-0024-0000-0000-00000000000c';
  v_filas int;
  v_age int;
begin
  insert into auth.users (id, email, raw_user_meta_data)
  values (v_c, 'c-pub@example.test', '{"display_name":"Carla"}'::jsonb);
  update public.profiles_private set birth_date = null where user_id = v_c;

  set local role authenticated;
  set local request.jwt.claims = '{"sub":"aaaaaaaa-0024-0000-0000-00000000000a"}';

  select count(*), max(age) into v_filas, v_age
    from public.public_profiles where user_id = v_c;

  if v_filas <> 1 then
    raise exception 'Caso 6 FALLA: quien no tiene fecha de nacimiento desaparece de la vista '
                    '(% filas). El left join existe justo para esto.', v_filas;
  end if;
  if v_age is not null then
    raise exception 'Caso 6 FALLA: sin fecha de nacimiento la edad debería ser NULL, es %', v_age;
  end if;

  raise notice 'Caso 6 OK: sin fecha de nacimiento se ve el perfil, sin edad';
end $$;

rollback;
