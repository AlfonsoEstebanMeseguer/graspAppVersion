-- Test de RLS de la mensajería (Fase 4, Tarea 3): `conversations`, `conversation_states`
-- y `direct_messages`.
--
-- Punto 5 de la skill `rls-security`: una policy no se da por buena leyendo el SQL. Aquí importa
-- más que en ninguna otra tabla, porque cuatro reglas de la spec se cumplen POR LA FORMA de estas
-- tablas y no por código, así que si la forma está mal no hay endpoint que lo arregle después:
--
--   RN-06 — al emisor nunca se le enseña que su conversación quedó en `ignored`. Se sostiene sobre
--           que `conversations` NO TIENE NI UN GRANT: se comprueba en el caso 1.
--   RN-31 — no hay confirmación de lectura. Se sostiene sobre que el `unread_count` del otro vive
--           en una fila que no se puede leer: caso 6.
--   RN-27 — "borrar historial" solo vacía MI lado: caso 5.
--   RN-28 — "borrar para mí" solo me lo oculta a MÍ: caso 4.
--
-- CÓMO SE EJECUTA
--     docker exec -i supabase_db_backend psql -U postgres -d postgres \
--       -v ON_ERROR_STOP=1 < apps/backend/supabase/tests/messaging-rls.sql
--
-- Todo corre dentro de una transacción que termina en ROLLBACK: no deja rastro.
--
-- CÓMO SE SIMULA UN USUARIO CONCRETO
-- Igual que en `user-follows-rls.sql`: `set local role authenticated` para que apliquen los GRANT
-- de ese rol (no los de `postgres`, que es superusuario y se salta RLS) más
-- `set local request.jwt.claims`, de donde lee `auth.uid()`.

begin;

-- =====================================================================================
-- Caso 0: A, B y C dados de alta, y una conversación A<->B con dos mensajes
-- =====================================================================================
-- Los uuid se eligen para que A < B en orden de uuid, que es lo que exige
-- `conversations_ordered_pair`. C queda fuera de la conversación a propósito.
do $$
declare
  v_a uuid := 'aaaaaaaa-0003-0000-0000-00000000000a';
  v_b uuid := 'bbbbbbbb-0003-0000-0000-00000000000b';
  v_c uuid := 'cccccccc-0003-0000-0000-00000000000c';
  v_conv uuid := '11111111-0003-4000-8000-000000000001';
begin
  insert into auth.users (id, email, raw_user_meta_data) values
    (v_a, 'a-msg@example.test', '{"display_name":"Ana"}'::jsonb),
    (v_b, 'b-msg@example.test', '{"display_name":"Bruno"}'::jsonb),
    (v_c, 'c-msg@example.test', '{"display_name":"Carla"}'::jsonb);

  insert into public.conversations (id, user_a_id, user_b_id, status, initiator_id)
  values (v_conv, v_a, v_b, 'pending', v_a);

  insert into public.conversation_states (conversation_id, user_id) values
    (v_conv, v_a), (v_conv, v_b);

  insert into public.direct_messages (id, conversation_id, sender_id, content, created_at) values
    ('22222222-0003-4000-8000-000000000001', v_conv, v_a, 'primero',  now() - interval '2 hours'),
    ('22222222-0003-4000-8000-000000000002', v_conv, v_a, 'segundo',  now() - interval '1 hour');

  raise notice 'Caso 0 OK: A, B y C dados de alta; conversacion con 2 mensajes';
end $$;

-- =====================================================================================
-- Caso 1: `conversations` no tiene NI UN privilegio para authenticated ni para anon
-- =====================================================================================
-- Es la mitad estructural de RN-06 y el invariante de la Tarea 3. No se comprueba leyendo la
-- migración (punto 11 de rls-security): se pregunta a information_schema, que es la autoridad.
do $$
declare
  v_privs text;
begin
  select coalesce(string_agg(distinct grantee || ':' || privilege_type, ', '), '(ninguno)')
    into v_privs
    from information_schema.table_privileges
   where table_schema = 'public' and table_name = 'conversations'
     and grantee in ('anon', 'authenticated');

  assert v_privs = '(ninguno)',
    'conversations NO debe tener ningun privilegio para anon/authenticated (RN-06); tiene: ' || v_privs;

  assert not exists (
    select 1 from pg_policies where schemaname = 'public' and tablename = 'conversations'
  ), 'conversations no debe tener ninguna policy: es deny by default a proposito';

  raise notice 'Caso 1 OK: conversations sin grants ni policies (RN-06 estructural)';
end $$;

-- =====================================================================================
-- Caso 2: un participante lee los mensajes de su conversación; un tercero NO
-- =====================================================================================
do $$
declare
  v_a int;
  v_c int;
begin
  set local role authenticated;
  set local request.jwt.claims = '{"sub":"aaaaaaaa-0003-0000-0000-00000000000a"}';
  select count(*) into v_a from public.direct_messages;
  reset role;

  set local role authenticated;
  set local request.jwt.claims = '{"sub":"cccccccc-0003-0000-0000-00000000000c"}';
  select count(*) into v_c from public.direct_messages;
  reset role;

  assert v_a = 2, 'A debe ver los 2 mensajes de su conversacion; vio: ' || v_a;
  assert v_c = 0, 'C, ajeno a la conversacion, no debe ver NINGUN mensaje; vio: ' || v_c;

  raise notice 'Caso 2 OK: el participante lee, el tercero no ve nada';
end $$;

-- =====================================================================================
-- Caso 3: C no puede colarse fabricándose una fila en conversation_states
-- =====================================================================================
-- La policy de `direct_messages` deriva la participación de `conversation_states`. Si el cliente
-- pudiera insertar ahí, se metería en cualquier conversación. Por eso esa tabla NO tiene policy
-- de insert ni grant de insert — y esto lo comprueba, en vez de confiar en que se ha escrito.
do $$
declare
  v_rechazado boolean := false;
begin
  set local role authenticated;
  set local request.jwt.claims = '{"sub":"cccccccc-0003-0000-0000-00000000000c"}';
  begin
    insert into public.conversation_states (conversation_id, user_id)
    values ('11111111-0003-4000-8000-000000000001', 'cccccccc-0003-0000-0000-00000000000c');
  exception when others then
    v_rechazado := true;
  end;
  reset role;

  assert v_rechazado,
    'C no debe poder insertarse en conversation_states: seria colarse en la conversacion';

  raise notice 'Caso 3 OK: no se puede fabricar la participacion';
end $$;

-- =====================================================================================
-- Caso 4: RN-28 — "borrar para mí" oculta el mensaje SOLO a quien lo borró
-- =====================================================================================
do $$
declare
  v_a int;
  v_b int;
begin
  update public.direct_messages
     set deleted_for = array['aaaaaaaa-0003-0000-0000-00000000000a'::uuid]
   where id = '22222222-0003-4000-8000-000000000001';

  set local role authenticated;
  set local request.jwt.claims = '{"sub":"aaaaaaaa-0003-0000-0000-00000000000a"}';
  select count(*) into v_a from public.direct_messages;
  reset role;

  set local role authenticated;
  set local request.jwt.claims = '{"sub":"bbbbbbbb-0003-0000-0000-00000000000b"}';
  select count(*) into v_b from public.direct_messages;
  reset role;

  assert v_a = 1, 'A borro un mensaje para si: debe ver 1; vio: ' || v_a;
  assert v_b = 2, 'B no borro nada: debe seguir viendo los 2; vio: ' || v_b;

  raise notice 'Caso 4 OK: deleted_for oculta solo a quien borro (RN-28)';
end $$;

-- =====================================================================================
-- Caso 5: RN-27 — `cleared_at` vacía SOLO el lado de quien borró el historial
-- =====================================================================================
do $$
declare
  v_a int;
  v_b int;
begin
  -- B borra su historial: no debe ver nada anterior a este momento.
  update public.conversation_states
     set cleared_at = now()
   where conversation_id = '11111111-0003-4000-8000-000000000001'
     and user_id = 'bbbbbbbb-0003-0000-0000-00000000000b';

  set local role authenticated;
  set local request.jwt.claims = '{"sub":"bbbbbbbb-0003-0000-0000-00000000000b"}';
  select count(*) into v_b from public.direct_messages;
  reset role;

  set local role authenticated;
  set local request.jwt.claims = '{"sub":"aaaaaaaa-0003-0000-0000-00000000000a"}';
  select count(*) into v_a from public.direct_messages;
  reset role;

  assert v_b = 0, 'B borro su historial: no debe ver nada anterior; vio: ' || v_b;
  assert v_a = 1, 'A no borro su historial: su vista no cambia; vio: ' || v_a;

  raise notice 'Caso 5 OK: cleared_at vacia solo el lado propio (RN-27)';
end $$;

-- =====================================================================================
-- Caso 6: RN-31 — nadie puede leer el `unread_count` del otro
-- =====================================================================================
-- Es la comprobación que hace real la ausencia de confirmación de lectura: no hace falta prohibir
-- `read_at` en el código si la fila del otro sencillamente no se puede consultar.
do $$
declare
  v_propias int;
  v_ajenas  int;
begin
  update public.conversation_states set unread_count = 7
   where conversation_id = '11111111-0003-4000-8000-000000000001'
     and user_id = 'bbbbbbbb-0003-0000-0000-00000000000b';

  set local role authenticated;
  set local request.jwt.claims = '{"sub":"aaaaaaaa-0003-0000-0000-00000000000a"}';
  select count(*) into v_propias from public.conversation_states
   where user_id = 'aaaaaaaa-0003-0000-0000-00000000000a';
  select count(*) into v_ajenas from public.conversation_states
   where user_id = 'bbbbbbbb-0003-0000-0000-00000000000b';
  reset role;

  assert v_propias = 1, 'A debe ver su propia fila de estado; vio: ' || v_propias;
  assert v_ajenas = 0,
    'A NO debe poder leer la fila de estado de B: ahi vive su unread_count (RN-31); vio: ' || v_ajenas;

  raise notice 'Caso 6 OK: el unread_count del otro es ilegible (RN-31)';
end $$;

-- =====================================================================================
-- Caso 7: los grants de columna de conversation_states
-- =====================================================================================
-- `unread_count` y `notifications_enabled` los escribe el cliente; `hidden` y `cleared_at` NO:
-- archivar es efecto de bloquear (RN-22) y vaciar el historial (RN-27) tiene consecuencias.
do $$
declare
  v_hidden_rechazado  boolean := false;
  v_cleared_rechazado boolean := false;
  v_unread_ok         boolean := true;
begin
  set local role authenticated;
  set local request.jwt.claims = '{"sub":"aaaaaaaa-0003-0000-0000-00000000000a"}';

  begin
    update public.conversation_states set hidden = true
     where user_id = 'aaaaaaaa-0003-0000-0000-00000000000a';
  exception when others then
    v_hidden_rechazado := true;
  end;

  begin
    update public.conversation_states set cleared_at = now()
     where user_id = 'aaaaaaaa-0003-0000-0000-00000000000a';
  exception when others then
    v_cleared_rechazado := true;
  end;

  begin
    update public.conversation_states set unread_count = 0
     where user_id = 'aaaaaaaa-0003-0000-0000-00000000000a';
  exception when others then
    v_unread_ok := false;
  end;

  reset role;

  assert v_hidden_rechazado,  'authenticated NO debe poder escribir hidden (RN-22 lo mueve el backend)';
  assert v_cleared_rechazado, 'authenticated NO debe poder escribir cleared_at (RN-27 lo mueve el backend)';
  assert v_unread_ok,         'authenticated SI debe poder poner su unread_count a 0';

  raise notice 'Caso 7 OK: grants de columna de conversation_states';
end $$;

-- =====================================================================================
-- Caso 8: RN-08 — el par ordenado y su índice único impiden el hilo duplicado
-- =====================================================================================
do $$
declare
  v_invertido boolean := false;
  v_duplicado boolean := false;
begin
  -- El par al revés lo rechaza el CHECK, así que (B,A) no puede existir como fila distinta de (A,B).
  begin
    insert into public.conversations (user_a_id, user_b_id, initiator_id)
    values ('bbbbbbbb-0003-0000-0000-00000000000b', 'aaaaaaaa-0003-0000-0000-00000000000a',
            'bbbbbbbb-0003-0000-0000-00000000000b');
  exception when others then
    v_invertido := true;
  end;

  -- Y el mismo par otra vez lo rechaza el indice unico.
  begin
    insert into public.conversations (user_a_id, user_b_id, initiator_id)
    values ('aaaaaaaa-0003-0000-0000-00000000000a', 'bbbbbbbb-0003-0000-0000-00000000000b',
            'bbbbbbbb-0003-0000-0000-00000000000b');
  exception when others then
    v_duplicado := true;
  end;

  assert v_invertido, 'El par invertido (B,A) debe rechazarlo conversations_ordered_pair';
  assert v_duplicado, 'El par repetido (A,B) debe rechazarlo conversations_pair_key (RN-08)';

  raise notice 'Caso 8 OK: no puede haber dos hilos para el mismo par (RN-08)';
end $$;

-- =====================================================================================
-- Caso 9: la lápida de RN-28 y el check de contenido
-- =====================================================================================
do $$
declare
  v_sin_contenido boolean := false;
  v_solo_espacios boolean := false;
  v_lapida_con_texto boolean := false;
begin
  begin
    insert into public.direct_messages (conversation_id, sender_id)
    values ('11111111-0003-4000-8000-000000000001', 'aaaaaaaa-0003-0000-0000-00000000000a');
  exception when others then
    v_sin_contenido := true;
  end;

  -- char_length('   ') es 3: sin el btrim, esto pasaria el `between 1 and 1000`.
  begin
    insert into public.direct_messages (conversation_id, sender_id, content)
    values ('11111111-0003-4000-8000-000000000001', 'aaaaaaaa-0003-0000-0000-00000000000a', '   ');
  exception when others then
    v_solo_espacios := true;
  end;

  -- Una lapida con el texto todavia dentro es justo lo que el check existe para impedir: si el
  -- contenido sobreviviera, cualquier cliente que ignorase la bandera lo pintaria igual.
  begin
    insert into public.direct_messages (conversation_id, sender_id, content, deleted_for_all_at)
    values ('11111111-0003-4000-8000-000000000001', 'aaaaaaaa-0003-0000-0000-00000000000a',
            'sigo aqui', now());
  exception when others then
    v_lapida_con_texto := true;
  end;

  assert v_sin_contenido,    'Un mensaje sin contenido ni lapida debe rechazarse';
  assert v_solo_espacios,    'Un mensaje de solo espacios debe rechazarse (btrim)';
  assert v_lapida_con_texto, 'Una lapida con content no NULL debe rechazarse';

  raise notice 'Caso 9 OK: el check de contenido y lapida (RN-28)';
end $$;

-- =====================================================================================
-- Caso 10: `direct_messages` está publicada en supabase_realtime
-- =====================================================================================
-- Sin esto no hay entrega en tiempo real y el fallo es MUDO: la app no recibe nada y no hay
-- ningun error que lo delate. De ahi que sea un caso de test y no una comprobación manual.
do $$
begin
  assert exists (
    select 1 from pg_publication_tables
     where pubname = 'supabase_realtime'
       and schemaname = 'public' and tablename = 'direct_messages'
  ), 'direct_messages debe estar en la publicacion supabase_realtime';

  raise notice 'Caso 10 OK: direct_messages publicada en supabase_realtime';
end $$;

-- =====================================================================================
-- Caso 11: anon no tiene nada en ninguna de las tres
-- =====================================================================================
do $$
declare
  v_privs text;
begin
  select coalesce(string_agg(distinct table_name || ':' || privilege_type, ', '), '(ninguno)')
    into v_privs
    from information_schema.table_privileges
   where table_schema = 'public'
     and table_name in ('conversations', 'conversation_states', 'direct_messages')
     and grantee = 'anon';

  assert v_privs = '(ninguno)',
    'anon no debe tener ningun privilegio de mensajeria; tiene: ' || v_privs;

  raise notice 'Caso 11 OK: anon sin privilegios de mensajeria';
end $$;

rollback;
