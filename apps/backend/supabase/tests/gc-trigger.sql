-- Test del trigger de recogida de basura de fotos de perfil.
--
-- Cubre la cascada de la Sección 24 del documento maestro:
--     borrado → trigger → storage_gc_queue → media-gc-cron → borrado en R2
-- (este fichero llega hasta la cola; el drenado en R2 lo hace la Edge Function).
--
-- CÓMO SE EJECUTA
--     docker exec -i supabase_db_backend psql -U postgres -d postgres \
--       -v ON_ERROR_STOP=1 -f - < apps/backend/supabase/tests/gc-trigger.sql
--
-- Todo corre dentro de una transacción que termina en ROLLBACK: no deja rastro.
--
-- POR QUÉ SE REESCRIBIÓ (2026-08-10)
-- La versión anterior insertaba directamente en `public.profiles` un `user_id` fijo
-- que no existía en `auth.users`, así que violaba `profiles_user_id_fkey` y NUNCA
-- llegó a ejecutarse una sola vez. Además solo probaba el borrado del PERFIL, que
-- es el camino que sí funcionaba; el borrado de la CUENTA —el que de verdad ocurre
-- cuando alguien ejerce el derecho al olvido— estaba roto y nadie lo sabía. Ese es
-- ahora el caso 3.

begin;

-- =====================================================================================
-- Caso 0: existen el trigger y su función
-- =====================================================================================
do $$
begin
  assert exists (
    select 1 from pg_trigger
     where tgname = 'profiles_on_delete_queue_photo'
       and tgrelid = 'public.profiles'::regclass
  ), 'Debe existir el trigger profiles_on_delete_queue_photo sobre public.profiles';

  assert exists (
    select 1 from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where p.proname = 'queue_profile_photo_for_deletion'
       and n.nspname = 'public'
  ), 'Debe existir la función public.queue_profile_photo_for_deletion';

  raise notice 'Caso 0 OK: trigger y función presentes';
end $$;

-- =====================================================================================
-- Caso 1: borrar el PERFIL con foto encola la clave
-- =====================================================================================
-- El usuario se crea en auth.users, no en profiles: `on_auth_user_created` ya crea
-- la fila de profiles por nosotros, así que aquí solo se le pone la foto.
do $$
declare
  v_user_id uuid := '11111111-1111-1111-1111-111111111111';
  v_photo   text := 'avatars/11111111-1111-1111-1111-111111111111/foto.webp';
  v_filas   int;
begin
  -- `display_name` es obligatorio desde el ADR 0018: sin metadata, `handle_new_user` rechaza el
  -- alta y este caso fallaría antes de llegar a probar nada de la cascada.
  insert into auth.users (id, email, raw_user_meta_data)
  values (v_user_id, 'gc-caso1@example.test', '{"display_name":"GC Caso 1"}'::jsonb);
  update public.profiles set photo_path = v_photo where user_id = v_user_id;

  assert (select photo_path from public.profiles where user_id = v_user_id) = v_photo,
    'El perfil debería tener la foto asignada antes de borrarlo';

  delete from public.profiles where user_id = v_user_id;

  select count(*) into v_filas
    from public.storage_gc_queue
   where user_id = v_user_id and photo_path = v_photo and status = 'pending';

  assert v_filas = 1,
    'Borrar el perfil debe encolar exactamente una foto; encontradas: ' || v_filas;

  raise notice 'Caso 1 OK: borrar el perfil encola la foto';
end $$;

-- =====================================================================================
-- Caso 2: borrar un perfil sin foto no encola nada
-- =====================================================================================
do $$
declare
  v_user_id uuid := '22222222-2222-2222-2222-222222222222';
  v_filas   int;
begin
  insert into auth.users (id, email, raw_user_meta_data)
  values (v_user_id, 'gc-caso2@example.test', '{"display_name":"GC Caso 2"}'::jsonb);

  assert (select photo_path from public.profiles where user_id = v_user_id) is null,
    'El perfil recién creado no debería tener photo_path';

  delete from public.profiles where user_id = v_user_id;

  select count(*) into v_filas from public.storage_gc_queue where user_id = v_user_id;

  assert v_filas = 0,
    'Un perfil sin foto no debe encolar nada; encontradas: ' || v_filas;

  raise notice 'Caso 2 OK: sin foto no se encola nada';
end $$;

-- =====================================================================================
-- Caso 3: borrar la CUENTA encola la foto Y la cola sobrevive al usuario
-- =====================================================================================
-- Este es el camino del derecho al olvido (Art. 17 RGPD) y el que estaba roto hasta
-- 20260810140000: la FK de storage_gc_queue contra auth.users hacía fallar el propio
-- DELETE, y la de photo_audit_log lo impedía con un RESTRICT.
--
-- Que la fila siga en la cola DESPUÉS de que el usuario ya no exista es el corazón
-- del test: si volviera un `on delete cascade`, la fila desaparecería y el objeto de
-- R2 quedaría huérfano para siempre sin que nada fallara de forma visible.
do $$
declare
  v_user_id uuid := '33333333-3333-3333-3333-333333333333';
  v_photo   text := 'avatars/33333333-3333-3333-3333-333333333333/foto.webp';
  v_filas   int;
begin
  insert into auth.users (id, email, raw_user_meta_data)
  values (v_user_id, 'gc-caso3@example.test', '{"display_name":"GC Caso 3"}'::jsonb);
  update public.profiles set photo_path = v_photo where user_id = v_user_id;

  -- Una entrada de auditoría, para cubrir de paso el RESTRICT que bloqueaba el borrado.
  insert into public.photo_audit_log (user_id, photo_path, action)
    values (v_user_id, v_photo, 'uploaded');

  delete from auth.users where id = v_user_id;

  assert not exists (select 1 from auth.users where id = v_user_id),
    'El usuario debe haberse borrado';
  assert not exists (select 1 from public.profiles where user_id = v_user_id),
    'El perfil debe haber caído por cascada';

  select count(*) into v_filas
    from public.storage_gc_queue
   where user_id = v_user_id and photo_path = v_photo and status = 'pending';

  assert v_filas = 1,
    'Borrar la cuenta debe dejar la foto encolada y la fila debe SOBREVIVIR al usuario; '
    'encontradas: ' || v_filas;

  select count(*) into v_filas
    from public.photo_audit_log where user_id = v_user_id;

  assert v_filas = 1,
    'La auditoría debe sobrevivir al borrado de la cuenta (Art. 6.1.c); encontradas: ' || v_filas;

  raise notice 'Caso 3 OK: el borrado de cuenta funciona y deja la cola y la auditoría vivas';
end $$;

-- =====================================================================================
-- Caso 4: la cola nunca queda expuesta a anon/authenticated
-- =====================================================================================
-- La cola contiene claves de R2 de todo el mundo. Un grant suelto aquí filtraría el
-- inventario de fotos del servicio entero.
do $$
declare
  v_grants text;
begin
  select coalesce(string_agg(distinct grantee || ':' || privilege_type, ', '), '(ninguno)')
    into v_grants
    from information_schema.role_table_grants
   where table_schema = 'public'
     and table_name in ('storage_gc_queue', 'photo_audit_log')
     and grantee in ('anon', 'authenticated');

  assert v_grants = '(ninguno)',
    'anon/authenticated no deben tener ningún grant sobre la cola ni la auditoría; hay: ' || v_grants;

  raise notice 'Caso 4 OK: sin grants para anon/authenticated';
end $$;

rollback;
