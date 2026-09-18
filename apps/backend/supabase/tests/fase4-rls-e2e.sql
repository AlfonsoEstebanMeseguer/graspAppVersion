-- Prueba de RLS de extremo a extremo de la Fase 4, con TRES CLIENTES (Tarea 17).
--
-- Punto 5 de la skill `rls-security`: una policy no se da por buena leyendo el SQL. Los tres
-- clientes son `authenticated` como A, `authenticated` como B —el vecino legítimo, que es más
-- peligroso que un desconocido porque SÍ tiene sesión y SÍ participa en algo— y `anon`, que es el
-- que siempre se olvida y cuya clave va **embebida en la app**: cualquiera la tiene.
--
-- POR QUÉ ESTE FICHERO EXISTE APARTE, y no dentro de `messaging-rls.sql` como decía el plan:
-- aquí se comprueban `profiles.tag`, `profiles_private.last_seen_at` y la frontera del Art. 9,
-- que no son mensajería. Meterlo allí dejaría un fichero cuyo nombre miente sobre lo que cubre, y
-- este repositorio ya tiene el precedente de un documento leído como si fuera el estado del
-- sistema (punto 6 de `rls-security`).
--
-- LO QUE NO SE REPITE AQUÍ, porque ya está probado y duplicarlo crea dos sitios que mantener:
--   · RN-23, que B no ve la fila donde A le bloqueó → `moderation-rls.sql`, caso 1.
--   · `anon` tabla por tabla en mensajería y Conectar → `messaging-rls.sql` caso 11,
--     `connect-purge.sql` caso 2, `moderation-rls.sql` caso 6.
--   · Que los RPC no los ejecute `anon` → `activity-status.sql` caso 7, `follow-counters.sql` caso 5.
--
-- CÓMO SE EJECUTA
--     docker exec -i supabase_db_backend psql -U postgres -d postgres \
--       -v ON_ERROR_STOP=1 < apps/backend/supabase/tests/fase4-rls-e2e.sql
--
-- Todo corre dentro de una transacción que termina en ROLLBACK: no deja rastro.
--
-- CÓMO SE SIMULA UN USUARIO: `set local role authenticated` para que apliquen los GRANT de ese rol
-- —y no los de `postgres`, que es superusuario y se salta RLS entera— más `set local
-- request.jwt.claims`, de donde lee `auth.uid()`.

begin;

-- =====================================================================================
-- Caso 0: A, B y C, con DOS conversaciones — A<->B y A<->C
-- =====================================================================================
-- La segunda conversación es el punto del caso 2: B no es un desconocido, es participante de
-- A<->B. Un test en el que el intruso no participa en NADA no distingue una policy que acota por
-- conversación de una que solo pregunta "¿tienes alguna conversación?".
-- Los uuid se eligen con a < b < c para satisfacer `conversations_ordered_pair`.
do $$
declare
  v_a uuid := 'aaaaaaaa-0017-0000-0000-00000000000a';
  v_b uuid := 'bbbbbbbb-0017-0000-0000-00000000000b';
  v_c uuid := 'cccccccc-0017-0000-0000-00000000000c';
  v_ab uuid := '11111111-0017-4000-8000-00000000ab00';
  v_ac uuid := '11111111-0017-4000-8000-00000000ac00';
begin
  insert into auth.users (id, email, raw_user_meta_data) values
    (v_a, 'a-e2e@example.test', '{"display_name":"Ana"}'::jsonb),
    (v_b, 'b-e2e@example.test', '{"display_name":"Bruno"}'::jsonb),
    (v_c, 'c-e2e@example.test', '{"display_name":"Carla"}'::jsonb);

  insert into public.conversations (id, user_a_id, user_b_id, status, initiator_id) values
    (v_ab, v_a, v_b, 'accepted', v_a),
    (v_ac, v_a, v_c, 'accepted', v_a);

  insert into public.conversation_states (conversation_id, user_id) values
    (v_ab, v_a), (v_ab, v_b),
    (v_ac, v_a), (v_ac, v_c);

  insert into public.direct_messages (conversation_id, sender_id, content) values
    (v_ab, v_a, 'hola Bruno'),
    (v_ab, v_b, 'hola Ana'),
    (v_ac, v_a, 'esto es solo para Carla');

  raise notice 'Caso 0 OK: A, B y C con dos conversaciones (A-B y A-C)';
end $$;

-- =====================================================================================
-- Caso 1: leer `conversations` como A tiene que FALLAR con 42501, no devolver 0 filas
-- =====================================================================================
-- ES EL CASO QUE DISTINGUE LAS DOS CAPAS (punto 10 de `rls-security`). Con RLS activo y sin
-- policy, un `select` devuelve **cero filas en silencio**; sin `GRANT`, revienta con
-- `permission denied for table`. Los dos "protegen" hoy, pero no son intercambiables: RN-06 se
-- sostiene sobre el GRANT, y si mañana alguien concede `select` a `authenticated` creyendo que la
-- policy ya cubre, la tabla pasa de inaccesible a "vacía" — y basta una policy permissive
-- posterior para abrirla entera.
--
-- Por eso no vale mirar `information_schema` (eso ya lo hace `messaging-rls.sql` caso 1): hay que
-- EJECUTAR la consulta y comprobar que el error es el del privilegio.
do $$
declare
  v_state text := '(no hubo error)';
  v_msg   text := '';
  v_filas int  := -1;
begin
  set local role authenticated;
  set local request.jwt.claims = '{"sub":"aaaaaaaa-0017-0000-0000-00000000000a"}';
  begin
    select count(*) into v_filas from public.conversations;
  exception when others then
    v_state := SQLSTATE;
    v_msg   := SQLERRM;
  end;
  reset role;

  assert v_state = '42501',
    'Leer conversations como A debe fallar con 42501 (el GRANT), no devolver filas. Estado: '
    || v_state || ', filas devueltas: ' || v_filas;
  assert v_msg like '%permission denied%',
    'El rechazo debe venir del GRANT y no de la policy (punto 10 de rls-security). Mensaje: ' || v_msg;

  raise notice 'Caso 1 OK: conversations rechaza por privilegio (42501), no por policy';
end $$;

-- =====================================================================================
-- Caso 2: B participa en A<->B, y aun así NO ve los mensajes de A<->C
-- =====================================================================================
do $$
declare
  v_b int;
  v_c int;
  v_b_ajenos int;
begin
  set local role authenticated;
  set local request.jwt.claims = '{"sub":"bbbbbbbb-0017-0000-0000-00000000000b"}';
  select count(*) into v_b from public.direct_messages;
  select count(*) into v_b_ajenos from public.direct_messages
   where conversation_id = '11111111-0017-4000-8000-00000000ac00';
  reset role;

  set local role authenticated;
  set local request.jwt.claims = '{"sub":"cccccccc-0017-0000-0000-00000000000c"}';
  select count(*) into v_c from public.direct_messages;
  reset role;

  assert v_b = 2, 'B debe ver los 2 mensajes de SU conversacion; vio: ' || v_b;
  assert v_b_ajenos = 0,
    'B NO debe ver ningun mensaje de la conversacion A-C, aunque sea participante de otra; vio: '
    || v_b_ajenos;
  assert v_c = 1, 'C debe ver solo el mensaje de su conversacion; vio: ' || v_c;

  raise notice 'Caso 2 OK: la policy acota POR CONVERSACION, no por "tener alguna"';
end $$;

-- =====================================================================================
-- Caso 3: A no puede escribirse su propio `tag`
-- =====================================================================================
-- El tag es inmutable para el usuario: lo acuña el servidor y lo rota `profile-tag-rotate`. Si el
-- cliente pudiera escribirlo, «inmutable» sería una promesa del front, no del sistema — y alguien
-- podría okupar el tag de otra persona, que es la única forma de encontrar a alguien (RN-11).
do $$
declare
  v_tag_rechazado    boolean := false;
  v_nombre_permitido boolean := true;
  v_msg text := '';
begin
  set local role authenticated;
  set local request.jwt.claims = '{"sub":"aaaaaaaa-0017-0000-0000-00000000000a"}';

  begin
    update public.profiles set tag = 'okupa#ZZZZZZZZ'
     where user_id = 'aaaaaaaa-0017-0000-0000-00000000000a';
  exception when others then
    v_tag_rechazado := true;
    v_msg := SQLERRM;
  end;

  -- LA OTRA MITAD, y no es decorativa: si TODO estuviera prohibido, este test pasaria con los
  -- grants revocados enteros y no probaria nada sobre `tag` en concreto.
  begin
    update public.profiles set display_name = 'Ana editada'
     where user_id = 'aaaaaaaa-0017-0000-0000-00000000000a';
  exception when others then
    v_nombre_permitido := false;
  end;

  reset role;

  assert v_tag_rechazado, 'A NO debe poder escribir su propio tag (lo acuna el servidor)';
  assert v_msg like '%permission denied%',
    'El rechazo del tag debe venir del GRANT de columna, no de una policy. Mensaje: ' || v_msg;
  assert v_nombre_permitido, 'A SI debe poder editar su display_name (si no, el test es vacuo)';

  raise notice 'Caso 3 OK: tag no escribible, display_name si';
end $$;

-- =====================================================================================
-- Caso 4: `last_seen_at` y `tag_rotated_at` no los escribe el usuario; `hide_activity_status` sí
-- =====================================================================================
-- `last_seen_at` lo mueve solo el RPC `touch_last_seen`. Si el cliente pudiera escribirlo, podría
-- fingirse activo para siempre — o, peor, retroceder el reloj de otro modo de espiar (RN-30).
do $$
declare
  v_last_seen_rechazado boolean := false;
  v_rotated_rechazado   boolean := false;
  v_hide_permitido      boolean := true;
begin
  set local role authenticated;
  set local request.jwt.claims = '{"sub":"aaaaaaaa-0017-0000-0000-00000000000a"}';

  begin
    update public.profiles_private set last_seen_at = now()
     where user_id = 'aaaaaaaa-0017-0000-0000-00000000000a';
  exception when others then
    v_last_seen_rechazado := true;
  end;

  begin
    update public.profiles_private set tag_rotated_at = null
     where user_id = 'aaaaaaaa-0017-0000-0000-00000000000a';
  exception when others then
    v_rotated_rechazado := true;
  end;

  -- La mitad permitida: RN-32 la controla el usuario, así que esta SÍ tiene que dejarle.
  begin
    update public.profiles_private set hide_activity_status = true
     where user_id = 'aaaaaaaa-0017-0000-0000-00000000000a';
  exception when others then
    v_hide_permitido := false;
  end;

  reset role;

  assert v_last_seen_rechazado, 'last_seen_at NO es escribible por el usuario (solo touch_last_seen)';
  assert v_rotated_rechazado,
    'tag_rotated_at NO es escribible por el usuario: si lo fuera, el tope de 1 rotacion/24 h de '
    || 'RN-21 se saltaria poniendolo a null';
  assert v_hide_permitido, 'hide_activity_status SI lo controla el usuario (RN-32)';

  raise notice 'Caso 4 OK: last_seen_at y tag_rotated_at cerrados, hide_activity_status abierto';
end $$;

-- =====================================================================================
-- Caso 5: A tiene el GRANT sobre `unread_count`, y aun así no puede tocar el de B
-- =====================================================================================
-- El grant de columna deja pasar la COLUMNA (A puede poner su propio contador a 0); lo que impide
-- tocar la fila de B son las POLICIES.
--
-- EN PLURAL, Y COMPROBADO ROMPIÉNDOLO (2026-08-25): un `update … where user_id = 'B'` está
-- protegido por DOS policies a la vez, no por una. La de `update` decide qué filas se pueden
-- modificar, y la de `select` interviene también porque el `WHERE` **lee** una columna. Relajar
-- solo una de las dos a `using (true)` deja el caso pasando igual: hacen falta las dos para que
-- A alcance la fila de B.
--
-- Importa para quien audite: una mutación de UNA capa no demuestra que esa capa esté sosteniendo
-- algo. Si al relajar la policy de `update` este test sigue verde, no es que el test sea vacuo —
-- es que la de `select` está tapando el agujero, y al revés. La verificación completa está en la
-- skill `rls-security`, punto 15.
do $$
declare
  v_b_antes int;
  v_b_despues int;
  v_afectadas int;
begin
  update public.conversation_states set unread_count = 7
   where conversation_id = '11111111-0017-4000-8000-00000000ab00'
     and user_id = 'bbbbbbbb-0017-0000-0000-00000000000b';

  select unread_count into v_b_antes from public.conversation_states
   where conversation_id = '11111111-0017-4000-8000-00000000ab00'
     and user_id = 'bbbbbbbb-0017-0000-0000-00000000000b';

  set local role authenticated;
  set local request.jwt.claims = '{"sub":"aaaaaaaa-0017-0000-0000-00000000000a"}';
  -- No lanza excepción: la policy hace que el UPDATE no ENCUENTRE la fila. Por eso se cuenta lo
  -- afectado en vez de esperar un error — un `assert` sobre una excepción que nunca llega pasaría
  -- solo, y este es justo el caso en que las dos capas se comportan distinto.
  update public.conversation_states set unread_count = 0
   where user_id = 'bbbbbbbb-0017-0000-0000-00000000000b';
  get diagnostics v_afectadas = row_count;
  reset role;

  select unread_count into v_b_despues from public.conversation_states
   where conversation_id = '11111111-0017-4000-8000-00000000ab00'
     and user_id = 'bbbbbbbb-0017-0000-0000-00000000000b';

  assert v_b_antes = 7, 'preparacion: el contador de B deberia valer 7; vale ' || v_b_antes;
  assert v_afectadas = 0,
    'A no debe poder actualizar NINGUNA fila de B; afecto a ' || v_afectadas;
  assert v_b_despues = 7,
    'El unread_count de B no debe haber cambiado (RN-31); vale ' || v_b_despues;

  raise notice 'Caso 5 OK: el grant deja la columna, la policy salva la fila (RN-31)';
end $$;

-- =====================================================================================
-- Caso 6: A no puede leer el `profiles_private` de B — la frontera del Art. 9
-- =====================================================================================
-- `profiles_private` guarda `primary_category_id` y `secondary_categories`, que son categoría
-- especial del Art. 9 RGPD. `connect-feed` los lee con `service_role` y devuelve un número; esta
-- comprobación es la que garantiza que NO hay ningún otro camino desde el cliente.
do $$
declare
  v_propias int;
  v_ajenas  int;
begin
  set local role authenticated;
  set local request.jwt.claims = '{"sub":"aaaaaaaa-0017-0000-0000-00000000000a"}';
  select count(*) into v_propias from public.profiles_private
   where user_id = 'aaaaaaaa-0017-0000-0000-00000000000a';
  select count(*) into v_ajenas from public.profiles_private
   where user_id = 'bbbbbbbb-0017-0000-0000-00000000000b';
  reset role;

  assert v_propias = 1, 'A debe leer su propia fila privada; leyo: ' || v_propias;
  assert v_ajenas = 0,
    'A NO debe leer el profiles_private de B: ahi viven las categorias del Art. 9; leyo: ' || v_ajenas;

  raise notice 'Caso 6 OK: las categorias del Art. 9 son ilegibles para terceros';
end $$;

-- =====================================================================================
-- Caso 7: el tercer cliente — `anon` no lee NADA de la superficie de la Fase 4
-- =====================================================================================
-- El rol de la clave publicable, que viaja embebida en la app. Aquí no se mira
-- `information_schema` (eso es el caso 8): se INTENTA de verdad, tabla por tabla.
do $$
declare
  v_tabla      text;
  v_rechazadas int := 0;
  v_total      int := 0;
  v_coladas    text := '';
  v_tablas     text[] := array[
    'conversations', 'conversation_states', 'direct_messages', 'user_follows',
    'blocks', 'reports', 'connect_dismissals', 'connect_impressions', 'connect_feed_runs',
    'profiles', 'profiles_private'
  ];
begin
  set local role anon;
  foreach v_tabla in array v_tablas loop
    v_total := v_total + 1;
    begin
      execute format('select 1 from public.%I limit 1', v_tabla);
      v_coladas := v_coladas || v_tabla || ' ';
    exception when others then
      v_rechazadas := v_rechazadas + 1;
    end;
  end loop;
  reset role;

  assert v_rechazadas = v_total,
    'anon no debe poder leer ninguna tabla de la Fase 4; se colo en: ' || v_coladas;

  raise notice 'Caso 7 OK: anon rechazado en las % tablas', v_total;
end $$;

-- =====================================================================================
-- Caso 7b: `anon` tampoco escribe — y bloquear en nombre de otro es lo más grave
-- =====================================================================================
do $$
declare
  v_block_rechazado  boolean := false;
  v_follow_rechazado boolean := false;
begin
  set local role anon;

  begin
    insert into public.blocks (blocker_id, blocked_id)
    values ('aaaaaaaa-0017-0000-0000-00000000000a', 'bbbbbbbb-0017-0000-0000-00000000000b');
  exception when others then
    v_block_rechazado := true;
  end;

  begin
    insert into public.user_follows (follower_id, followee_id)
    values ('bbbbbbbb-0017-0000-0000-00000000000b', 'aaaaaaaa-0017-0000-0000-00000000000a');
  exception when others then
    v_follow_rechazado := true;
  end;

  reset role;

  assert v_block_rechazado, 'anon NO debe poder insertar un bloqueo en nombre de nadie';
  assert v_follow_rechazado, 'anon NO debe poder insertar un follow en nombre de nadie';

  raise notice 'Caso 7b OK: anon no escribe en blocks ni en user_follows';
end $$;

-- =====================================================================================
-- Caso 8: la matriz de grants REAL, para los tres roles (paso 2 de la Tarea 17)
-- =====================================================================================
-- Punto 11 de `rls-security`: el estado no se deduce leyendo migraciones — puede haber otra
-- anterior. `information_schema` es la única autoridad.
do $$
declare
  v_anon      text;
  v_prof_upd  text;
  v_priv_upd  text;
  v_state_upd text;
begin
  -- --- anon: cero, en tabla Y en columna. `revoke ... from authenticated` no alcanza a `anon`.
  select coalesce(string_agg(distinct table_name || ':' || privilege_type, ', '), '(ninguno)')
    into v_anon
    from information_schema.table_privileges
   where table_schema = 'public'
     and table_name in ('conversations','conversation_states','direct_messages','user_follows',
                        'blocks','reports','connect_dismissals','connect_impressions',
                        'connect_feed_runs','profiles','profiles_private')
     and grantee = 'anon';
  assert v_anon = '(ninguno)', 'anon no debe tener NINGUN privilegio en la Fase 4; tiene: ' || v_anon;

  -- --- authenticated, UPDATE por columna. Se comprueba la lista EXACTA, no que contenga: una
  --     columna de mas es justo el fallo del punto 9 (autoconcederse `level`, `vip_status`…).
  select string_agg(column_name, ', ' order by column_name) into v_prof_upd
    from information_schema.column_privileges
   where table_schema='public' and table_name='profiles'
     and grantee='authenticated' and privilege_type='UPDATE';
  assert v_prof_upd = 'bio, display_name, language',
    'UPDATE de authenticated sobre profiles debe ser exactamente (bio, display_name, language); es: '
    || coalesce(v_prof_upd, '(ninguna)');

  select string_agg(column_name, ', ' order by column_name) into v_priv_upd
    from information_schema.column_privileges
   where table_schema='public' and table_name='profiles_private'
     and grantee='authenticated' and privilege_type='UPDATE';
  assert v_priv_upd = 'birth_date, country, gender, hide_activity_status',
    'UPDATE sobre profiles_private debe excluir last_seen_at y tag_rotated_at; es: '
    || coalesce(v_priv_upd, '(ninguna)');

  select string_agg(column_name, ', ' order by column_name) into v_state_upd
    from information_schema.column_privileges
   where table_schema='public' and table_name='conversation_states'
     and grantee='authenticated' and privilege_type='UPDATE';
  assert v_state_upd = 'notifications_enabled, unread_count',
    'UPDATE sobre conversation_states debe excluir hidden y cleared_at; es: '
    || coalesce(v_state_upd, '(ninguna)');

  raise notice 'Caso 8 OK: matriz de grants de anon y authenticated';
end $$;

-- =====================================================================================
-- Caso 9: `service_role` tiene el DML que cada Edge Function necesita
-- =====================================================================================
-- Punto 12 de `rls-security`: `service_role` tiene BYPASSRLS pero NO BYPASSGRANT, y desde que
-- `20260809142046` revocó los default privileges, una tabla nueva TAMPOCO nace con permisos para
-- él. El síntoma de olvidarlo es el backend entero en 500 (`permission denied for table X`) en
-- cualquier entorno creado desde cero — y el entorno viejo, cuyas tablas nacieron con los grants
-- antiguos, lo tapa. Por eso se comprueba aquí y no en el despliegue.
do $$
declare
  r      record;
  v_req  text;
  v_falta text := '';
begin
  for r in
    select * from (values
      ('conversations',       array['SELECT','INSERT','UPDATE','DELETE']),
      ('conversation_states', array['SELECT','INSERT','UPDATE','DELETE']),
      ('direct_messages',     array['SELECT','INSERT','UPDATE','DELETE']),
      ('user_follows',        array['SELECT','INSERT','UPDATE','DELETE']),
      -- `blocks` y `reports` sin UPDATE a propósito: un bloqueo se crea o se borra, no se edita.
      ('blocks',              array['SELECT','INSERT','DELETE']),
      ('reports',             array['SELECT','INSERT','DELETE']),
      ('connect_dismissals',  array['SELECT','INSERT','UPDATE','DELETE']),
      ('connect_impressions', array['SELECT','INSERT','UPDATE','DELETE']),
      ('connect_feed_runs',   array['SELECT','INSERT','UPDATE','DELETE'])
    ) as t(tabla, requeridos)
  loop
    foreach v_req in array r.requeridos loop
      if not exists (
        select 1 from information_schema.table_privileges
         where table_schema='public' and table_name=r.tabla
           and grantee='service_role' and privilege_type=v_req
      ) then
        v_falta := v_falta || r.tabla || '.' || v_req || ' ';
      end if;
    end loop;
  end loop;

  assert v_falta = '',
    'service_role sin el DML que necesita (backend en 500 en un entorno nuevo): ' || v_falta;

  raise notice 'Caso 9 OK: service_role con DML suficiente en las 9 tablas';
end $$;

-- =====================================================================================
-- Caso 10: el RPC del contador de refrescos no lo ejecuta el cliente (Tarea 16)
-- =====================================================================================
-- `bump_connect_refresh` recibe el `user_id` por parámetro, así que si `authenticated` pudiera
-- llamarlo podría gastar —o regalarse— los refrescos de cualquiera. Punto 11 de `db-schema`:
-- toda función de `public` es un RPC de PostgREST salvo que se revoque.
do $$
declare
  v_auth_rechazado boolean := false;
  v_anon_rechazado boolean := false;
begin
  set local role authenticated;
  set local request.jwt.claims = '{"sub":"aaaaaaaa-0017-0000-0000-00000000000a"}';
  begin
    perform public.bump_connect_refresh('aaaaaaaa-0017-0000-0000-00000000000a');
  exception when others then
    v_auth_rechazado := true;
  end;
  reset role;

  set local role anon;
  begin
    perform public.bump_connect_refresh('aaaaaaaa-0017-0000-0000-00000000000a');
  exception when others then
    v_anon_rechazado := true;
  end;
  reset role;

  assert v_auth_rechazado, 'authenticated NO debe poder ejecutar bump_connect_refresh';
  assert v_anon_rechazado, 'anon NO debe poder ejecutar bump_connect_refresh';

  raise notice 'Caso 10 OK: bump_connect_refresh solo para service_role';
end $$;

rollback;
