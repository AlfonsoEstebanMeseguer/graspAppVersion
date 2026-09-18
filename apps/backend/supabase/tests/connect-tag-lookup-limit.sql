-- Test de `public.bump_tag_lookup` y de la purga de `connect_tag_lookups` (ADR 0028 §5).
--
-- CÓMO SE EJECUTA
--     docker exec -i supabase_db_backend psql -U postgres -d postgres \
--       -v ON_ERROR_STOP=1 < apps/backend/supabase/tests/connect-tag-lookup-limit.sql
--
-- Todo corre dentro de una transacción que termina en ROLLBACK: no deja rastro.
--
-- TODOS LOS RECUENTOS VAN ACOTADOS A LAS FILAS QUE SIEMBRA ESTA SUITE. Es la lección de
-- `connect-purge.sql`, que se ponía rojo porque alguien había navegado por Conectar: un `count(*)`
-- sobre la tabla entera mide el uso de la base, no el código.

begin;

-- =====================================================================================
-- Caso 0: el contador SUBE, y la segunda llamada devuelve 2 y no 1 dos veces
-- =====================================================================================
-- Es el control de todo lo demás: si el incremento no subiera, cualquier tope pasaría a ser
-- infinito y todos los casos de abajo seguirían verdes.
do $$
declare
  v uuid := 'cccccccc-0028-4000-8000-00000000000c';
  n1 int; n2 int; n3 int;
begin
  insert into auth.users (id, email, raw_user_meta_data)
  values (v, 'v28@grasp.test', '{"display_name":"Vic 28"}'::jsonb);

  n1 := public.bump_tag_lookup(v);
  n2 := public.bump_tag_lookup(v);
  n3 := public.bump_tag_lookup(v);

  assert n1 = 1, format('la primera busqueda debe devolver 1, devolvio %s', n1);
  assert n2 = 2, format('la segunda debe devolver 2 y no 1 otra vez, devolvio %s', n2);
  assert n3 = 3, format('la tercera debe devolver 3, devolvio %s', n3);

  raise notice 'Caso 0 OK: el contador sube';
end $$;

-- =====================================================================================
-- Caso 1: el cupo es POR USUARIO — el de uno no gasta el del otro
-- =====================================================================================
do $$
declare
  v uuid := 'cccccccc-0028-4000-8000-00000000000c';
  o uuid := 'dddddddd-0028-4000-8000-00000000000d';
  n int;
begin
  insert into auth.users (id, email, raw_user_meta_data)
  values (o, 'o28@grasp.test', '{"display_name":"Oti 28"}'::jsonb);

  -- V ya lleva 3 del caso 0.
  n := public.bump_tag_lookup(o);
  assert n = 1, format('el contador de O debe empezar en 1, no heredar los 3 de V; devolvio %s', n);

  assert (select lookup_count from public.connect_tag_lookups
           where user_id = v and looked_on = current_date) = 3,
    'el contador de V no debe haberse movido al buscar O';

  raise notice 'Caso 1 OK: el cupo es por usuario';
end $$;

-- =====================================================================================
-- Caso 2: el cupo es POR DÍA — la fila de ayer no cuenta para hoy
-- =====================================================================================
-- No hay ninguna lógica de caducidad que probar: la fecha va en la PK y el calendario la hace sola.
-- Lo que se comprueba es justo eso — que una fila de ayer con el cupo agotado NO afecta a hoy.
do $$
declare
  e uuid := 'eeeeeeee-0028-4000-8000-00000000000e';
  n int;
begin
  insert into auth.users (id, email, raw_user_meta_data)
  values (e, 'e28@grasp.test', '{"display_name":"Eva 28"}'::jsonb);

  insert into public.connect_tag_lookups (user_id, looked_on, lookup_count)
  values (e, current_date - 1, 999);

  n := public.bump_tag_lookup(e);
  assert n = 1,
    format('una fila de AYER con el cupo agotado no debe contar para hoy; devolvio %s', n);

  raise notice 'Caso 2 OK: el cupo se reinicia con el calendario';
end $$;

-- =====================================================================================
-- Caso 3: GRANTS — solo `service_role` puede ejecutar el RPC
-- =====================================================================================
-- Sin esto el RPC es un arma: recibe el `user_id` por parametro, asi que cualquier usuario
-- registrado podria gastarle el cupo a otro y dejarlo sin la unica forma que hay de encontrar a
-- alguien a proposito (§6.2). Es denegacion de servicio dirigida, no una fuga de datos.
do $$
declare
  v_oid oid;
begin
  reset role;   -- `set local role` dura toda la TRANSACCION: sin esto se hereda el rol anterior

  select p.oid into v_oid
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'bump_tag_lookup';

  assert v_oid is not null, 'la funcion bump_tag_lookup no existe';
  assert has_function_privilege('service_role', v_oid, 'EXECUTE'),
    'service_role necesita EXECUTE o connect-tag-lookup devuelve 500';
  assert not has_function_privilege('authenticated', v_oid, 'EXECUTE'),
    'authenticated NO debe poder ejecutarla: recibe el user_id por parametro';
  assert not has_function_privilege('anon', v_oid, 'EXECUTE'),
    'anon NO debe poder ejecutarla';

  raise notice 'Caso 3 OK: solo service_role la ejecuta';
end $$;

-- =====================================================================================
-- Caso 4: la TABLA es deny by default para el cliente
-- =====================================================================================
do $$
begin
  reset role;

  assert (select relrowsecurity from pg_class
           where oid = 'public.connect_tag_lookups'::regclass),
    'connect_tag_lookups debe tener RLS activo';

  assert not exists (select 1 from pg_policies
                      where schemaname = 'public' and tablename = 'connect_tag_lookups'),
    'connect_tag_lookups no debe tener ninguna policy: la escribe solo service_role';

  assert not has_table_privilege('authenticated', 'public.connect_tag_lookups', 'SELECT'),
    'authenticated NO debe poder leer el contador de nadie';
  assert not has_table_privilege('anon', 'public.connect_tag_lookups', 'SELECT'),
    'anon NO debe poder leerlo';

  raise notice 'Caso 4 OK: deny by default';
end $$;

-- =====================================================================================
-- Caso 5: LA PURGA — y se ejecuta el comando literal del cron, no una copia
-- =====================================================================================
-- Si alguien renombra la funcion y no toca el `cron.schedule`, este caso se pone rojo. Una copia a
-- mano de la sentencia seguiria verde mientras el cron lleva meses fallando cada madrugada.
do $$
declare
  f uuid := 'ffffffff-0028-4000-8000-00000000000f';
  v_command text;
begin
  insert into auth.users (id, email, raw_user_meta_data)
  values (f, 'f28@grasp.test', '{"display_name":"Fer 28"}'::jsonb);

  insert into public.connect_tag_lookups (user_id, looked_on, lookup_count)
  values (f, current_date - 8, 12),   -- vieja: se purga
         (f, current_date - 3, 7),    -- dentro de los 7 dias: se queda
         (f, current_date,     2);    -- de hoy: se queda

  select command into v_command from cron.job where jobname = 'connect-purge';
  assert v_command is not null, 'el cron connect-purge no esta programado';

  execute v_command;

  assert not exists (select 1 from public.connect_tag_lookups
                      where user_id = f and looked_on = current_date - 8),
    'la purga debe borrar las filas de mas de 7 dias de connect_tag_lookups';
  assert exists (select 1 from public.connect_tag_lookups
                  where user_id = f and looked_on = current_date - 3),
    'la purga NO debe tocar las filas de dentro de los 7 dias';
  assert exists (select 1 from public.connect_tag_lookups
                  where user_id = f and looked_on = current_date),
    'la purga NO debe tocar las de hoy: son el cupo en curso';

  raise notice 'Caso 5 OK: la purga alcanza a la tabla nueva';
end $$;

-- =====================================================================================
-- Caso 6: borrar la cuenta se lleva su contador (Art. 17)
-- =====================================================================================
do $$
declare
  v uuid := 'cccccccc-0028-4000-8000-00000000000c';
begin
  assert exists (select 1 from public.connect_tag_lookups where user_id = v),
    'control: V debe tener contador antes de borrar la cuenta';

  delete from auth.users where id = v;

  assert not exists (select 1 from public.connect_tag_lookups where user_id = v),
    'borrar la cuenta debe llevarse su contador: la FK va con on delete cascade';

  raise notice 'Caso 6 OK: la cascada alcanza al contador';
end $$;

rollback;
