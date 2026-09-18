-- =================================================================================================
-- Fase 4 · Tarea 10 (añadido) — la entrega de un mensaje: `last_message_at`, `unread_count`, `hidden`.
--
-- Plan: docs/superpowers/plans/2026-08-23-contactos-y-mensajeria.md (Tarea 10, paso 3)
-- Spec: docs/spec-contactos-mensajes-conectar.md (RN-06, RN-07, RN-27, RN-29, RN-31)
-- ADR:  docs/decisions/0023-el-ignorar-sobrevive-a-los-mensajes-pendientes.md
--
-- ESTA MIGRACIÓN NO ESTÁ EN LA LISTA DE FICHEROS DE LA TAREA 10, y se añade a propósito — igual que
-- `20260823120600_follow_counters.sql` en la Tarea 8, y por un motivo emparentado pero NO idéntico.
--
-- POR QUÉ NO SE PUEDE HACER DESDE LA EDGE FUNCTION
--   · PostgREST no admite expresiones en un `UPDATE`: `unread_count = unread_count + 1` no se puede
--     pedir desde el cliente Supabase.
--   · Leer-modificar-escribir desde Deno es una carrera: dos envíos simultáneos leen el mismo valor
--     y escriben el mismo incremento, y el contador se queda corto.
--
-- POR QUÉ UN TRIGGER Y NO UNA FUNCIÓN QUE SE LLAMA DESPUÉS, QUE ES LO QUE HIZO LA TAREA 8
-- Aquí está la diferencia que decide el diseño, y conviene no copiar `sync_follow_counters` sin
-- verla: aquella función RECALCULA desde `user_follows`, así que es autocorrectiva — si una llamada
-- falla, la siguiente arregla el número, y por eso `follow-toggle` puede permitirse un
-- `console.warn` y seguir.
--
-- **Lo no leído no se deriva de ninguna tabla.** `read_at` está PROHIBIDA por RN-31 «ahora ni nunca»
-- (ADR 0021), así que no existe fuente de verdad desde la que recalcular y no hay nada con qué
-- comparar el contador. Es decir: un incremento perdido es PERMANENTE y además INDETECTABLE. Un RPC
-- posterior al `insert` puede perderse —el mensaje commitea, la llamada muere— y deja exactamente
-- ese daño.
--
-- Un trigger `after insert` corre en LA MISMA TRANSACCIÓN que el mensaje: o hay mensaje y contador,
-- o no hay ninguno de los dos. Y como vive en el camino de escritura y no en el de edición
-- (`db-schema` punto 4d), lo cumple TODO camino por el que pueda nacer una fila — la Edge Function
-- de hoy, y la importación o el webhook de mañana, sin que nadie se acuerde.
-- =================================================================================================

create or replace function public.on_direct_message_insert()
returns trigger
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_status    text;
  v_recipient uuid;
begin
  -- El receptor es el participante que no escribió. El par está ORDENADO
  -- (`user_a_id < user_b_id`), así que no se puede deducir del orden: hay que compararlo.
  select c.status,
         case when c.user_a_id = new.sender_id then c.user_b_id else c.user_a_id end
    into v_status, v_recipient
    from public.conversations c
   where c.id = new.conversation_id;

  -- La FK lo garantiza, pero un trigger que asume y falla en silencio es peor que uno que sale.
  if not found then
    return new;
  end if;

  -- --- RN-29: orden de la lista de Contactos.
  --
  -- SE ACTUALIZA TAMBIÉN EN UNA CONVERSACIÓN `ignored`, y es obligatorio que así sea: es la mitad
  -- de RN-06 que se olvida. Al emisor su conversación tiene que seguir comportándose EXACTAMENTE
  -- como una pendiente, y una que dejara de ascender en su lista al escribir sería observable.
  --
  -- El guardia `<` impide que una escritura fuera de orden (una importación con `created_at`
  -- pasado) haga retroceder la lista.
  update public.conversations
     set last_message_at = new.created_at
   where id = new.conversation_id
     and last_message_at < new.created_at;

  -- --- El EMISOR: RN-27. Si había borrado su historial, volver a escribir le devuelve la
  -- conversación —vacía, porque su `cleared_at` sigue puesto y la policy de `direct_messages` solo
  -- le muestra lo posterior. Nunca se le toca `unread_count`: lo propio no se cuenta como no leído
  -- (RN-31).
  update public.conversation_states
     set hidden = false
   where conversation_id = new.conversation_id
     and user_id = new.sender_id;

  -- --- El RECEPTOR: el `+1` atómico de RN-31 y la reaparición de RN-27, en una sola sentencia.
  --
  -- SALVO SI LA CONVERSACIÓN ESTÁ `ignored` (RN-06, RN-07), y esto ENMIENDA el paso 3 de la Tarea
  -- 10, que pedía `hidden = false` «en los dos». No se puede: el paso 1 de la Tarea 12 hace del
  -- `hidden` del receptor EL mecanismo del ignorar, así que limpiarlo aquí significa que los
  -- mensajes 2..5 del emisor DESHACEN el rechazo y le devuelven a la bandeja una conversación que
  -- pidió no ver. `ignored` es TERMINAL (RN-07); RN-27 promete que una conversación reaparece
  -- cuando el otro escribe, pero eso es sobre un historial que el usuario BORRÓ, no sobre una
  -- conversación que RECHAZÓ.
  --
  -- El `unread_count` va en el mismo paquete y por su propio motivo: un badge que sube por una
  -- conversación que no aparece en ninguna de las dos pestañas del receptor es un número que no
  -- puede bajar nunca, porque no hay pantalla donde marcarlo leído. Un estado absorbente.
  --
  -- Y no filtra nada al emisor: no toca ninguna fila que él pueda leer (RN-06). Razones completas
  -- en el ADR 0023.
  if v_status <> 'ignored' then
    update public.conversation_states
       set unread_count = unread_count + 1,
           hidden       = false
     where conversation_id = new.conversation_id
       and user_id = v_recipient;
  end if;

  return new;
end;
$$;

comment on function public.on_direct_message_insert() is
  'Trigger `after insert` de `direct_messages`: sube `last_message_at` (RN-29), incrementa el '
  '`unread_count` del RECEPTOR (RN-31) y deshace el `hidden` de los dos (RN-27). Es un TRIGGER y no '
  'un RPC posterior porque lo no leido NO SE DERIVA de ninguna tabla —`read_at` esta prohibida por '
  'RN-31/ADR 0021—, asi que a diferencia de `sync_follow_counters` no es autocorrectivo: un '
  'incremento perdido seria permanente e indetectable. Correr en la misma transaccion que el '
  'mensaje es lo que lo impide. En una conversacion `ignored` NO toca nada del receptor (RN-06, '
  'RN-07, ADR 0023).';

-- `security definer`: escribe `conversations` y `conversation_states`, que son territorio del
-- backend. Así el trigger no depende de qué rol acabe insertando el mensaje.
--
-- Punto 11 de `db-schema`: se revoca `execute` igualmente. PostgREST no expone las funciones que
-- devuelven `trigger`, así que hoy no hay ruta para llamarla — pero la regla es la regla, cuesta una
-- línea, y el día que alguien cambie la firma la protección ya está puesta. Postgres no comprueba
-- `EXECUTE` del invocador al disparar un trigger, así que esto no impide que el trigger funcione.
revoke execute on function public.on_direct_message_insert() from public, anon, authenticated;

-- Idempotente: esta migración tiene que poder reaplicarse en un `db reset`.
drop trigger if exists direct_messages_delivery on public.direct_messages;

create trigger direct_messages_delivery
  after insert on public.direct_messages
  for each row
  execute function public.on_direct_message_insert();

-- =================================================================================================
-- VERIFICACIÓN POSTERIOR (a mano tras aplicar; la migración no la hace)
-- =================================================================================================
--   select tgname, tgenabled from pg_trigger
--    where tgrelid = 'public.direct_messages'::regclass and not tgisinternal;
--   -- direct_messages_delivery | O
--
--   -- Ningún `unread_count` puede superar los mensajes que el otro le mandó. No es una igualdad
--   -- —marcar como leído lo baja— pero un contador POR ENCIMA solo puede venir de un incremento de
--   -- más, y esta es la única consulta que lo delata:
--   select cs.conversation_id, cs.user_id, cs.unread_count
--     from public.conversation_states cs
--    where cs.unread_count > (
--            select count(*) from public.direct_messages dm
--             where dm.conversation_id = cs.conversation_id and dm.sender_id <> cs.user_id);
--   -- 0 filas.  Test: apps/backend/supabase/tests/message-delivery.sql

-- =================================================================================================
-- ROLLBACK:
-- =================================================================================================
-- drop trigger if exists direct_messages_delivery on public.direct_messages;
-- drop function if exists public.on_direct_message_insert();
