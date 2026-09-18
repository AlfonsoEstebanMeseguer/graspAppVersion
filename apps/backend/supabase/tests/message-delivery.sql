-- Test de `public.on_direct_message_insert` — el trigger de entrega (Fase 4, Tarea 10).
--
-- POR QUÉ ESTO ES UN TRIGGER Y NO UN `+1` DESDE LA EDGE FUNCTION, que es lo que este fichero fija:
--
--   · PostgREST no admite expresiones en un `UPDATE`, así que `unread_count = unread_count + 1` no
--     se puede pedir desde el cliente Supabase. Leer-modificar-escribir desde Deno es una carrera:
--     dos envíos simultáneos leen el mismo valor y escriben el mismo incremento.
--   · Y a diferencia de `sync_follow_counters` (Tarea 8), aquí NO SE PUEDE RECALCULAR. Los
--     seguidores se derivan de `user_follows`, así que aquel contador es autocorrectivo: llamarlo
--     otra vez arregla cualquier deriva. Lo no leído no se deriva de ninguna tabla — `read_at` está
--     PROHIBIDA por RN-31 y el ADR 0021 — así que **un incremento perdido es permanente y no hay
--     con qué compararlo**. Nadie lo detecta nunca.
--
-- De ahí el trigger: corre en LA MISMA TRANSACCIÓN que el `insert` del mensaje, así que el contador
-- no puede divergir de los mensajes que lo causaron ni aunque la Edge Function muera a media
-- petición. Un RPC posterior sí podría perderse (el mensaje commitea, la llamada falla).
--
-- CÓMO SE EJECUTA
--     docker exec -i supabase_db_backend psql -U postgres -d postgres \
--       -v ON_ERROR_STOP=1 < apps/backend/supabase/tests/message-delivery.sql

begin;

-- =====================================================================================
-- Caso 0: dos usuarios y una conversación `pending` con estado para los dos
-- =====================================================================================
-- OJO CON EL RELOJ: `now()` es CONSTANTE dentro de una transacción, así que
-- `last_message_at` se siembra explícitamente en el pasado. Si se dejara en `now()`,
-- el `assert` de "la conversación subió" compararía dos valores idénticos y pasaría
-- sin probar nada.
do $$
declare
  a uuid := 'aaaaaaaa-1010-4000-8000-00000000000a';  -- emisor  (user_a_id: 'aaaa' < 'bbbb')
  b uuid := 'bbbbbbbb-1010-4000-8000-00000000000b';  -- receptor
  v_conv uuid := 'cccccccc-1010-4000-8000-0000000000c1';
begin
  insert into auth.users (id, email, raw_user_meta_data) values
    (a, 'a-msg@example.test', '{"display_name":"Ana"}'::jsonb),
    (b, 'b-msg@example.test', '{"display_name":"Bruno"}'::jsonb);

  insert into public.conversations (id, user_a_id, user_b_id, status, initiator_id, last_message_at)
    values (v_conv, a, b, 'pending', a, now() - interval '1 hour');

  insert into public.conversation_states (conversation_id, user_id) values
    (v_conv, a), (v_conv, b);

  raise notice 'Caso 0 OK: conversacion pending con estado para los dos';
end $$;

-- =====================================================================================
-- Caso 1: el mensaje incrementa el `unread_count` del RECEPTOR y SOLO del receptor
-- =====================================================================================
-- RN-31: el contador es estrictamente local del receptor. Si el trigger tocara también el
-- del emisor, cada uno vería su propio envío como no leído — y peor, el número dejaría de
-- significar lo que dice.
do $$
declare
  a uuid := 'aaaaaaaa-1010-4000-8000-00000000000a';
  b uuid := 'bbbbbbbb-1010-4000-8000-00000000000b';
  v_conv uuid := 'cccccccc-1010-4000-8000-0000000000c1';
  v_a int;
  v_b int;
begin
  insert into public.direct_messages (conversation_id, sender_id, content)
    values (v_conv, a, 'Hola, ¿qué tal?');

  select unread_count into v_a from public.conversation_states
   where conversation_id = v_conv and user_id = a;
  select unread_count into v_b from public.conversation_states
   where conversation_id = v_conv and user_id = b;

  assert v_b = 1, 'El receptor debe tener 1 no leido; tiene: ' || v_b;
  assert v_a = 0, 'El EMISOR no debe acumular no leidos (RN-31); tiene: ' || v_a;

  raise notice 'Caso 1 OK: +1 solo al receptor';
end $$;

-- =====================================================================================
-- Caso 2: el incremento se ACUMULA — es un `+1` real, no un `set 1`
-- =====================================================================================
-- Un `update ... set unread_count = 1` pasaría el Caso 1 y fallaría aquí. Es justo el
-- error que un test de un solo mensaje no ve.
do $$
declare
  a uuid := 'aaaaaaaa-1010-4000-8000-00000000000a';
  b uuid := 'bbbbbbbb-1010-4000-8000-00000000000b';
  v_conv uuid := 'cccccccc-1010-4000-8000-0000000000c1';
  v_b int;
begin
  insert into public.direct_messages (conversation_id, sender_id, content)
    values (v_conv, a, 'Segundo mensaje');
  insert into public.direct_messages (conversation_id, sender_id, content)
    values (v_conv, a, 'Tercer mensaje');

  select unread_count into v_b from public.conversation_states
   where conversation_id = v_conv and user_id = b;

  assert v_b = 3, 'Tres mensajes deben dar 3 no leidos; da: ' || v_b;

  raise notice 'Caso 2 OK: el contador acumula';
end $$;

-- =====================================================================================
-- Caso 3: `last_message_at` sube al sello del mensaje (RN-29, orden de Contactos)
-- =====================================================================================
do $$
declare
  v_conv uuid := 'cccccccc-1010-4000-8000-0000000000c1';
  v_last timestamptz;
  v_msg  timestamptz;
begin
  select last_message_at into v_last from public.conversations where id = v_conv;
  select max(created_at) into v_msg from public.direct_messages where conversation_id = v_conv;

  assert v_last = v_msg,
    'last_message_at debe igualar el sello del ultimo mensaje; es ' || v_last || ' vs ' || v_msg;

  raise notice 'Caso 3 OK: last_message_at sigue al ultimo mensaje';
end $$;

-- =====================================================================================
-- Caso 4: RN-27 — escribir devuelve la conversación a quien la había ocultado
-- =====================================================================================
-- Los dos lados, porque son dos caminos distintos: el emisor recupera la suya por
-- escribir, y al receptor le reaparece porque le llega algo nuevo.
do $$
declare
  a uuid := 'aaaaaaaa-1010-4000-8000-00000000000a';
  b uuid := 'bbbbbbbb-1010-4000-8000-00000000000b';
  v_conv uuid := 'cccccccc-1010-4000-8000-0000000000c1';
  v_a_hidden boolean;
  v_b_hidden boolean;
begin
  update public.conversation_states set hidden = true
   where conversation_id = v_conv;

  insert into public.direct_messages (conversation_id, sender_id, content)
    values (v_conv, a, 'Sigo aqui');

  select hidden into v_a_hidden from public.conversation_states
   where conversation_id = v_conv and user_id = a;
  select hidden into v_b_hidden from public.conversation_states
   where conversation_id = v_conv and user_id = b;

  assert v_a_hidden = false, 'RN-27: al emisor le reaparece su conversacion al escribir';
  assert v_b_hidden = false, 'RN-27: al receptor le reaparece al recibir algo nuevo';

  raise notice 'Caso 4 OK: RN-27 en los dos lados de una conversacion pending';
end $$;

-- =====================================================================================
-- Caso 5: RN-06 — en una conversación IGNORADA no se le toca NADA al receptor
-- =====================================================================================
-- ES EL CASO QUE ENMIENDA EL PLAN. El paso 3 de la Tarea 10 decía «poner `hidden = false`
-- en los dos», pero el paso 1 de la Tarea 12 hace del `hidden` del receptor EL mecanismo
-- de RN-06 («`ignore` -> `status='ignored'` + `hidden` solo del receptor»). Aplicar los
-- dos pasos a la vez significa que los mensajes 2..5 del emisor DESHACEN el ignorar, y la
-- conversacion que el receptor rechazo le reaparece en la bandeja.
--
-- Manda RN-06/RN-07: `ignored` es TERMINAL. RN-27 promete que una conversacion reaparece
-- cuando el otro escribe, pero eso es sobre un historial que el usuario BORRO, no sobre una
-- conversacion que RECHAZO. Y el `unread_count` va en el mismo paquete: un badge que suma
-- por una conversacion que no aparece en ninguna de las dos pestañas es un numero que el
-- receptor no puede bajar nunca — un estado absorbente, ademas de un absurdo en la UI.
do $$
declare
  x uuid := 'dddddddd-1010-4000-8000-00000000000d';  -- emisor
  y uuid := 'eeeeeeee-1010-4000-8000-00000000000e';  -- receptor, que ignoro
  v_conv uuid := 'cccccccc-1010-4000-8000-0000000000c2';
  v_hidden boolean;
  v_unread int;
begin
  insert into auth.users (id, email, raw_user_meta_data) values
    (x, 'x-msg@example.test', '{"display_name":"Xime"}'::jsonb),
    (y, 'y-msg@example.test', '{"display_name":"Yago"}'::jsonb);

  insert into public.conversations (id, user_a_id, user_b_id, status, initiator_id, last_message_at)
    values (v_conv, x, y, 'ignored', x, now() - interval '1 hour');

  -- Como lo deja `messaging-actions` al ignorar (Tarea 12): oculta SOLO al receptor.
  insert into public.conversation_states (conversation_id, user_id, hidden) values
    (v_conv, x, false),
    (v_conv, y, true);

  insert into public.direct_messages (conversation_id, sender_id, content)
    values (v_conv, x, 'Segundo intento');

  select hidden, unread_count into v_hidden, v_unread
    from public.conversation_states where conversation_id = v_conv and user_id = y;

  assert v_hidden = true,
    'RN-06: una conversacion ignorada NO puede reaparecerle al receptor porque el emisor siga escribiendo';
  assert v_unread = 0,
    'RN-06: una conversacion ignorada no suma no leidos; da: ' || v_unread;

  raise notice 'Caso 5 OK: el ignorar sobrevive a los mensajes 2..5';
end $$;

-- =====================================================================================
-- Caso 6: RN-06 — y el EMISOR no nota absolutamente nada
-- =====================================================================================
-- La otra mitad, y la que se olvida: que el receptor quede intacto no puede pagarse con que
-- el emisor vea su conversacion congelada. Si `last_message_at` no subiera, su conversacion
-- dejaria de ascender en Contactos al escribir — observable, y por tanto una fuga de RN-06.
do $$
declare
  x uuid := 'dddddddd-1010-4000-8000-00000000000d';
  v_conv uuid := 'cccccccc-1010-4000-8000-0000000000c2';
  v_last timestamptz;
  v_msg  timestamptz;
  v_hidden boolean;
begin
  select last_message_at into v_last from public.conversations where id = v_conv;
  select max(created_at) into v_msg from public.direct_messages where conversation_id = v_conv;
  select hidden into v_hidden from public.conversation_states
   where conversation_id = v_conv and user_id = x;

  assert v_last = v_msg,
    'RN-06: en una ignorada `last_message_at` sube igual, o el emisor notaria que su hilo no asciende';
  assert v_hidden = false, 'RN-06: el emisor conserva su conversacion visible, como una pending';

  raise notice 'Caso 6 OK: el emisor no distingue una ignorada de una pendiente';
end $$;

rollback;
