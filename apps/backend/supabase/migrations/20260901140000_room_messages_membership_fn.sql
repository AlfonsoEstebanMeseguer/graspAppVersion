-- Salas de voz (Fase 5, Vuelta de arreglos 1): las policies de `room_messages` referencian
-- `room_participants.left_at`, y el `grant select` de esa tabla a `authenticated`
-- (20260901120000_rooms.sql, § "Nace sin permisos") NO incluye `left_at` -- a proposito, segun el
-- comentario de `rooms_feed` en esa misma migracion. Una policy se evalua con los permisos de quien
-- consulta, asi que un JWT de usuario normal no podia ni leer ni insertar en `room_messages`: el
-- chat de sala no funcionaba en ninguna direccion. Ningun test lo cazo porque `rooms-rls.sql` corre
-- como `postgres` (el dueno, que se salta los grants) y ningun caso ejercitaba `room_messages` bajo
-- `authenticated` -- tercera vez en esta fase que ese mismo patron esconde un permiso que falta
-- (antes con `service_role` y las siete funciones de escritura, dos veces).
--
-- La solucion NO es conceder `left_at`: eso amplia la superficie de lectura sin necesidad (esa
-- columna existe fuera del alcance de lo que `authenticated` necesita saber sobre otros
-- participantes -- ver el motivo de `rooms_feed` para el mismo campo). En su lugar, mismo patron ya
-- auditado en `rooms_feed`: una funcion `security definer` que acota exactamente lo que se puede
-- saber -- "¿soy miembro vivo de esta sala?", un booleano, nada de que sala ni de quien -- y que
-- depende de `auth.uid()` (resuelto del JWT via GUC de sesion), nunca de un parametro que se pueda
-- suplantar.
create or replace function public.is_room_member(p_room uuid)
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from room_participants
     where room_id = p_room and user_id = auth.uid() and left_at is null
  )
$$;

-- Por defecto `create function` concede EXECUTE a PUBLIC (que arrastra a `service_role`, punto 12 de
-- rls-security -- BYPASSRLS no es BYPASSGRANT). Se revoca todo y se concede solo a `authenticated`:
-- `service_role` no la necesita (se salta RLS por completo) y dejarla abierta la expondria igual
-- como RPC (`POST /rest/v1/rpc/is_room_member`) sin que nadie la llame por ese camino.
revoke all on function public.is_room_member(uuid) from public, anon, authenticated, service_role;
grant execute on function public.is_room_member(uuid) to authenticated;

drop policy if exists "room_messages_read_own_room" on public.room_messages;
create policy "room_messages_read_own_room" on public.room_messages
  for select to authenticated using (public.is_room_member(room_id));

drop policy if exists "room_messages_insert_own" on public.room_messages;
create policy "room_messages_insert_own" on public.room_messages
  for insert to authenticated with check (
    sender_id = auth.uid() and public.is_room_member(room_id)
  );

-- ROLLBACK:
-- drop policy if exists "room_messages_insert_own" on public.room_messages;
-- create policy "room_messages_insert_own" on public.room_messages
--   for insert to authenticated with check (
--     sender_id = auth.uid()
--     and exists (select 1 from public.room_participants p
--                  where p.room_id = room_messages.room_id
--                    and p.user_id = auth.uid() and p.left_at is null)
--   );
-- drop policy if exists "room_messages_read_own_room" on public.room_messages;
-- create policy "room_messages_read_own_room" on public.room_messages
--   for select to authenticated using (
--     exists (select 1 from public.room_participants p
--              where p.room_id = room_messages.room_id
--                and p.user_id = auth.uid() and p.left_at is null)
--   );
-- revoke execute on function public.is_room_member(uuid) from authenticated;
-- revoke all on function public.is_room_member(uuid) from public, anon, authenticated, service_role;
-- drop function if exists public.is_room_member(uuid);
