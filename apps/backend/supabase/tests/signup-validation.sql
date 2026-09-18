-- Test de las barreras del alta: `handle_new_user` valida en vez de copiar.
--
-- CÓMO SE EJECUTA
--     docker exec -i supabase_db_backend psql -U postgres -d postgres \
--       -v ON_ERROR_STOP=1 -f - < apps/backend/supabase/tests/signup-validation.sql
--
-- Todo corre dentro de una transacción que termina en ROLLBACK: no deja rastro.
--
-- QUÉ GUARDA, Y POR QUÉ AQUÍ
--
-- `profile-update` valida `display_name` (1-60), `gender` (enum) y `birth_date` (13-120 años). El
-- ALTA no pasa por ahí: pasa por este trigger, que hasta `20260816090000` copiaba
-- `raw_user_meta_data` con un `nullif(…,'')` como única transformación. Y ese `data` viaja en el
-- cuerpo de la petición a GoTrue, así que **lo elige quien llama**: la clave publicable va embebida
-- en la app, de modo que un `curl` podía poner ahí lo que quisiera y saltarse la validación entera
-- del proyecto simplemente registrándose otra vez (hallazgo H-SV-03).
--
-- Se prueba en SQL y no en Deno porque la barrera vive en la base de datos. Un test de la Edge
-- Function no la tocaría: el camino que hay que cubrir es justo el que NO pasa por ninguna función.
--
-- El caso 5 es el que impide que este fichero se vuelva vacuo. Una regla que lo rechaza todo pasa
-- los cuatro primeros casos y rompe el registro de la app entera.

begin;

-- =====================================================================================
-- Caso 1: menor de 13 años — Art. 8 RGPD
-- =====================================================================================
-- Es la barrera de consentimiento de menores, y hasta ahora solo se aplicaba al EDITAR el perfil,
-- nunca al crearlo. Una app de apoyo entre iguales en salud mental con salas de voz sin barrera de
-- edad en el único sitio donde se crean cuentas.
do $$
declare
  v_rechazado boolean := false;
begin
  begin
    -- `display_name` va en TODOS los casos negativos desde el 2026-08-17: es obligatorio, así
    -- que omitirlo haría que el alta se rechazara por el nombre y el caso pasaría sin haber
    -- probado la barrera que dice probar.
    insert into auth.users (id, email, raw_user_meta_data)
    values (gen_random_uuid(), 'menor@example.test',
            '{"display_name":"Menor","birth_date":"2020-01-01"}'::jsonb);
  exception when others then
    v_rechazado := true;
  end;

  assert v_rechazado, 'Un alta con menos de 13 anios debe rechazarse';
  raise notice 'Caso 1 OK: el alta de un menor de 13 se rechaza';
end $$;

-- =====================================================================================
-- Caso 2: `gender` fuera del enum
-- =====================================================================================
-- La columna es `text` sin enum de Postgres, así que sin esta comprobación el único sitio que lo
-- limitaba era `profile-update` — es decir, el camino que el atacante no usa.
do $$
declare
  v_rechazado boolean := false;
begin
  begin
    insert into auth.users (id, email, raw_user_meta_data)
    values (gen_random_uuid(), 'genero@example.test',
            '{"display_name":"Quien Sea","gender":"cualquier-cosa"}'::jsonb);
  exception when others then
    v_rechazado := true;
  end;

  assert v_rechazado, 'Un gender fuera del enum debe rechazarse en el alta';
  raise notice 'Caso 2 OK: gender fuera del enum se rechaza';
end $$;

-- =====================================================================================
-- Caso 3: `display_name` desmesurado
-- =====================================================================================
-- `display_name` es `text` sin límite y lo ve TODO EL MUNDO (`profiles_read_public` es
-- `using (true)`). Un nombre de un megabyte llegaba a la pantalla de cualquier usuario.
do $$
declare
  v_rechazado boolean := false;
begin
  begin
    insert into auth.users (id, email, raw_user_meta_data)
    values (
      gen_random_uuid(), 'largo@example.test',
      jsonb_build_object('display_name', repeat('x', 61))
    );
  exception when others then
    v_rechazado := true;
  end;

  assert v_rechazado, 'Un display_name de mas de 60 caracteres debe rechazarse';
  raise notice 'Caso 3 OK: display_name de 61 caracteres se rechaza';
end $$;

-- =====================================================================================
-- Caso 4: fecha no parseable — el fallo tiene que ser LIMPIO
-- =====================================================================================
-- Antes, `(nullif(meta->>'birth_date',''))::date` sobre basura lanzaba `invalid_datetime_format`
-- DENTRO del trigger y tumbaba el INSERT en auth.users entero: el alta devolvía un 500 opaco y
-- quien lo depurase no tenía forma de saber qué campo estaba mal.
do $$
declare
  v_sqlstate text;
begin
  begin
    insert into auth.users (id, email, raw_user_meta_data)
    values (gen_random_uuid(), 'basura@example.test',
            '{"display_name":"Fecha Mala","birth_date":"no-soy-fecha"}'::jsonb);
    assert false, 'Una fecha no parseable debe rechazarse';
  exception when others then
    v_sqlstate := sqlstate;
  end;

  -- 22007 es `invalid_datetime_format`: el cast crudo reventando. Debe ser 23514
  -- (`check_violation`), que es el que la función lanza a propósito.
  assert v_sqlstate = '23514',
    'La fecha invalida debe dar check_violation (23514), no el error crudo del cast; dio: '
    || v_sqlstate;

  raise notice 'Caso 4 OK: la fecha invalida falla limpio (23514), no con el error del cast';
end $$;

-- =====================================================================================
-- Caso 5: un alta VÁLIDA sigue funcionando — incluido el borde exacto de 13 años
-- =====================================================================================
-- Sin este caso, los cuatro anteriores los aprobaría una regla que rechaza todo, y el test daría
-- verde mientras nadie puede registrarse. Es el contra-test que impide que el fichero mienta.
do $$
declare
  v_user_id uuid := gen_random_uuid();
  v_borde   uuid := gen_random_uuid();
begin
  insert into auth.users (id, email, raw_user_meta_data)
  values (
    v_user_id, 'valido@example.test',
    '{"display_name":"Alfonso","gender":"hombre","birth_date":"1990-05-04"}'::jsonb
  );

  assert (select display_name from public.profiles where user_id = v_user_id) = 'Alfonso',
    'El alta valida debe crear el perfil con su nombre';
  assert (select gender from public.profiles_private where user_id = v_user_id) = 'hombre',
    'El alta valida debe guardar el gender en profiles_private';

  -- Justo 13 años cumplidos hoy: dentro. La comparación es `>`, no `>=`, y esa diferencia es la
  -- que decide si alguien puede registrarse el día de su cumpleaños.
  insert into auth.users (id, email, raw_user_meta_data)
  values (
    v_borde, 'borde@example.test',
    jsonb_build_object(
      'display_name', 'Justo Trece',
      'birth_date', to_char(current_date - interval '13 years', 'YYYY-MM-DD')
    )
  );

  assert exists (select 1 from public.profiles where user_id = v_borde),
    'Quien cumple 13 anios HOY debe poder registrarse';

  raise notice 'Caso 5 OK: el alta valida funciona, y el borde de 13 anios entra';
end $$;

-- =====================================================================================
-- Caso 6: `phone_number` ya no existe (H-S-01)
-- =====================================================================================
-- La columna era legible por cualquier usuario registrado: `grant select` de TABLA sobre una tabla
-- con la policy en `using (true)`. Se borró en vez de moverse (ADR 0015) porque no la usaba nadie y
-- porque lo que no se almacena no se puede volver a filtrar. Este caso existe para que reaparecer
-- cueste un test en rojo.
do $$
declare
  v_grants text;
begin
  assert not exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'profiles' and column_name = 'phone_number'
  ), 'profiles.phone_number no debe volver a existir (ADR 0015)';

  assert not exists (
    select 1 from pg_indexes
     where schemaname = 'public' and indexname = 'profiles_phone_number_idx'
  ), 'El indice del telefono no debe volver: es lo que hacia instantanea la busqueda inversa';

  -- Y la lectura de `profiles` sigue siendo de tabla para `authenticated`, así que cualquier
  -- columna nueva nace pública. Se deja escrito qué puede ESCRIBIR, que es lo que sí está acotado.
  select coalesce(string_agg(column_name, ', ' order by column_name), '(ninguna)')
    into v_grants
    from information_schema.column_privileges
   where table_schema = 'public' and table_name = 'profiles'
     and grantee = 'authenticated' and privilege_type = 'UPDATE';

  -- `bio` entró el 2026-08-25 (Fase 4, Tarea 1): es texto que escribe el usuario, como el nombre.
  assert v_grants = 'bio, display_name, language',
    'authenticated solo debe poder escribir bio, display_name y language; puede: ' || v_grants;

  -- `tag` NO entra en esa lista JAMÁS. Que el usuario no elija su tag (§6.2, RN-11: "inmutable"
  -- significa que no lo elige) es una garantía ESTRUCTURAL, no una comprobación dentro de
  -- `profile-tag-rotate` que alguien pueda rodear o quitar. Se asevera aparte del `=` de arriba
  -- a propósito: si un día alguien amplía la lista, este mensaje le dice POR QUÉ está mal en vez
  -- de limitarse a señalar que la cadena no coincide.
  assert not exists (
    select 1 from information_schema.column_privileges
     where table_schema = 'public' and table_name = 'profiles'
       and grantee = 'authenticated' and privilege_type = 'UPDATE' and column_name = 'tag'
  ), 'authenticated NO debe poder escribir profiles.tag: el usuario no elige su tag (§6.2, RN-11)';

  -- Y las dos columnas de `profiles_private` que sostienen mecanismos de backend. `last_seen_at`
  -- la escribe el RPC `touch_last_seen`: si la escribiera el cliente podría fingir actividad
  -- permanente. `tag_rotated_at` sostiene el tope de 1 rotación cada 24 h: si la escribiera el
  -- cliente, el tope no existiría.
  select coalesce(string_agg(column_name, ', ' order by column_name), '(ninguna)')
    into v_grants
    from information_schema.column_privileges
   where table_schema = 'public' and table_name = 'profiles_private'
     and grantee = 'authenticated' and privilege_type = 'UPDATE';

  assert v_grants = 'birth_date, country, gender, hide_activity_status',
    'authenticated no debe poder escribir last_seen_at ni tag_rotated_at; puede: ' || v_grants;

  -- `anon` no tiene nada en ninguna de las dos, y se comprueba aparte porque un
  -- `revoke ... from authenticated` NO le alcanza (punto 11 de rls-security).
  assert not exists (
    select 1 from information_schema.column_privileges
     where table_schema = 'public' and table_name in ('profiles', 'profiles_private')
       and grantee = 'anon'
  ), 'anon no debe tener ningun privilegio de columna sobre profiles ni profiles_private';

  raise notice 'Caso 6 OK: el telefono no ha vuelto y los grants de escritura siguen acotados';
end $$;

-- =====================================================================================
-- Caso 6b: el tag se acuna en el alta, y con el formato acunado (Fase 4, Tarea 1)
-- =====================================================================================
-- `handle_new_user` es el ÚNICO camino de alta, así que es el único sitio donde puede acuñarse
-- (punto 4d de db-schema). Si el acuñado se cayera del trigger, `tag` es `not null` y el alta
-- entera fallaría — pero el formato NO lo garantiza ninguna constraint, así que se comprueba aquí.
do $$
declare
  v_ruso  uuid := gen_random_uuid();
  v_tilde uuid := gen_random_uuid();
  v_tag_ruso  text;
  v_tag_tilde text;
begin
  insert into auth.users (id, email, raw_user_meta_data)
  values (v_ruso,  'tag-ruso@example.test',  '{"display_name":"Дмитрий"}'::jsonb),
         (v_tilde, 'tag-tilde@example.test', '{"display_name":"Alfonso Estebán"}'::jsonb);

  select tag into v_tag_ruso  from public.profiles where user_id = v_ruso;
  select tag into v_tag_tilde from public.profiles where user_id = v_tilde;

  -- El mismo regex que `isValidTag` en `_shared/tag.ts`. Alfabeto Crockford: sin I, L, O ni U.
  assert v_tag_ruso  ~ '^[a-z0-9]{1,12}#[0-9A-HJKMNP-TV-Z]{8}$',
    'El tag acunado en el alta debe encajar en el formato; es: ' || coalesce(v_tag_ruso, '(null)');
  assert v_tag_tilde ~ '^[a-z0-9]{1,12}#[0-9A-HJKMNP-TV-Z]{8}$',
    'El tag acunado en el alta debe encajar en el formato; es: ' || coalesce(v_tag_tilde, '(null)');

  -- Un nombre sin un solo caracter alfanumerico ASCII cae al fallback en vez de acunar '#XXXXXXXX'.
  assert split_part(v_tag_ruso, '#', 1) = 'grasp',
    'Un nombre entero en cirilico debe caer al fallback `grasp`; es: ' || v_tag_ruso;

  -- La tilde se separa y se cae, y la parte local se trunca a 12.
  assert split_part(v_tag_tilde, '#', 1) = 'alfonsoesteb',
    'La parte local debe perder la tilde y truncarse a 12; es: ' || v_tag_tilde;

  raise notice 'Caso 6b OK: el alta acuna el tag, con fallback y sin diacriticos';
end $$;

-- =====================================================================================
-- Caso 7: `display_name` es OBLIGATORIO (ADR 0018)
-- =====================================================================================
-- La constraint anterior (`display_name is null or char_length(...) between 1 and 60`) acotaba la
-- longitud y NO la presencia: un NULL satisface cualquier CHECK de Postgres. Se podía crear una
-- cuenta sin nombre por tres caminos a la vez — el trigger de alta, un PATCH directo a PostgREST
-- (display_name está en el grant de columna) y el formulario de registro, que no lo validaba.
-- Se prueban las tres formas de "sin nombre" porque cada una la para una pieza distinta.
do $$
declare
  v_ausente  boolean := false;
  v_vacio    boolean := false;
  v_espacios boolean := false;
  v_trim     uuid := gen_random_uuid();
begin
  begin
    insert into auth.users (id, email, raw_user_meta_data)
    values (gen_random_uuid(), 'sin-nombre@example.test', '{"gender":"otro"}'::jsonb);
  exception when others then
    v_ausente := true;
  end;
  assert v_ausente, 'Un alta SIN display_name debe rechazarse';

  begin
    insert into auth.users (id, email, raw_user_meta_data)
    values (gen_random_uuid(), 'vacio@example.test', '{"display_name":""}'::jsonb);
  exception when others then
    v_vacio := true;
  end;
  assert v_vacio, 'Un alta con display_name vacio debe rechazarse';

  -- El que se colaba aunque existiera la constraint vieja: char_length('   ') es 3, así que
  -- pasaba el `between 1 and 60`. Lo para el `btrim`.
  begin
    insert into auth.users (id, email, raw_user_meta_data)
    values (gen_random_uuid(), 'espacios@example.test', '{"display_name":"   "}'::jsonb);
  exception when others then
    v_espacios := true;
  end;
  assert v_espacios, 'Un alta con display_name de solo espacios debe rechazarse';

  -- Y el nombre llega recortado, para que el cliente y la constraint cuenten lo mismo.
  insert into auth.users (id, email, raw_user_meta_data)
  values (v_trim, 'recortado@example.test', '{"display_name":"  Ana Recortada  "}'::jsonb);

  assert (select display_name from public.profiles where user_id = v_trim) = 'Ana Recortada',
    'El nombre debe guardarse recortado, sin los espacios de los extremos';

  raise notice 'Caso 7 OK: display_name obligatorio (ausente, vacio y espacios) y recortado';
end $$;

-- =====================================================================================
-- Caso 8: la columna NO admite NULL ni por el camino directo
-- =====================================================================================
-- El caso 7 prueba el trigger; este prueba la tabla. Son barreras distintas: un `update` de
-- PostgREST no pasa por ningún trigger, y `authenticated` SÍ tiene `grant update (display_name)`.
-- Sin el `not null`, un PATCH con {"display_name": null} vaciaba el nombre de un perfil ya creado.
do $$
declare
  v_user_id  uuid := gen_random_uuid();
  v_rechazado boolean := false;
begin
  insert into auth.users (id, email, raw_user_meta_data)
  values (v_user_id, 'update-null@example.test', '{"display_name":"Tiene Nombre"}'::jsonb);

  begin
    update public.profiles set display_name = null where user_id = v_user_id;
  exception when others then
    v_rechazado := true;
  end;
  assert v_rechazado, 'Poner display_name a NULL con un update directo debe rechazarse';

  v_rechazado := false;
  begin
    update public.profiles set display_name = '  ' where user_id = v_user_id;
  exception when others then
    v_rechazado := true;
  end;
  assert v_rechazado, 'Dejar display_name en blanco con un update directo debe rechazarse';

  raise notice 'Caso 8 OK: la tabla rechaza el nombre nulo y el nombre en blanco';
end $$;

rollback;
