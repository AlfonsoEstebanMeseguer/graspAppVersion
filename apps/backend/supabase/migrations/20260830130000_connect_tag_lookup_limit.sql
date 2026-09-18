-- 20260830130000 — Tope diario de búsquedas por tag (ADR 0028, §5).
--
-- QUÉ ACOTA, Y QUÉ NO CIERRA
--
-- `connect-tag-lookup` responde IGUAL a un tag bloqueado que a un tag inexistente: mismo cuerpo,
-- mismo código (`RN-23`). No responde igual en TIEMPO —un bloqueo hace una consulta más— y el
-- ADR 0028 decide **no cerrar** ese canal: el tiempo constante artificial encarece el backend
-- entero y no compra nada mientras siga abierto el oráculo ACTIVO (intentar escribir y ver que
-- falla), que es una sola petición.
--
-- Lo que sí hace este tope es **acotarlo por volumen**: un ataque de latencia necesita muchísimas
-- muestras para separar dos distribuciones que se solapan, y con 30 al día no hay estadística que
-- valga. Y de paso cierra algo peor que no estaba anotado en ninguna parte: **la enumeración de
-- tags por fuerza bruta**. Sin tope, cualquier cuenta puede recorrer el espacio de tags a ritmo de
-- red y construirse un directorio de personas — exactamente lo que el §13 prohíbe al prohibir la
-- búsqueda difusa.
--
-- POR QUÉ SE CUENTAN TODAS LAS BÚSQUEDAS Y NO SOLO LAS QUE FALLAN
--
-- Un tope que solo contara los `404` sería **peor que no tener tope**: el contador se convertiría él
-- mismo en el oráculo que `RN-23` quiere cerrar, porque gastar cupo distinguiría un tag inexistente
-- de uno encontrado. Se incrementa SIEMPRE y ANTES de resolver, igual que `bump_connect_refresh`.

-- =================================================================================================
-- 1) La tabla — la fecha va DENTRO de la PK, como en las otras tres de Conectar
-- =================================================================================================
-- Con la fecha en la clave, el cupo se reinicia solo cada día: no hay ninguna lógica de caducidad
-- que escribir ni que acordarse de mantener. El calendario la hace sola.
create table if not exists public.connect_tag_lookups (
  user_id      uuid not null references public.profiles(user_id) on delete cascade,
  looked_on    date not null default current_date,
  lookup_count int  not null default 0 check (lookup_count >= 0),
  primary key (user_id, looked_on)
);

-- La PK empieza por `user_id`, así que la purga —que filtra SOLO por fecha— no la puede usar. Sin
-- este índice el barrido diario haría un seq scan que crece con el histórico entero. Mismo motivo,
-- y mismo remedio, que en `connect_impressions` y `connect_feed_runs`.
create index if not exists connect_tag_lookups_looked_on_idx
  on public.connect_tag_lookups (looked_on);

comment on table public.connect_tag_lookups is
  'ADR 0028: tope diario de busquedas por tag. La fecha va en la PK, asi que el contador se '
  'reinicia solo cada dia. Cuenta TODAS las busquedas, no solo las fallidas: un contador que solo '
  'subiera con los 404 distinguiria un tag inexistente de uno encontrado, y seria el oraculo que '
  'RN-23 quiere cerrar.';

-- =================================================================================================
-- 2) RLS — activo y SIN POLICIES. Deny by default.
-- =================================================================================================
-- Ningún cliente la toca: la lee y la escribe `connect-tag-lookup` con `service_role`, que tiene
-- BYPASSRLS. Sin policies, cualquier consulta con el JWT de un usuario devuelve cero filas; y sin
-- grant ni siquiera llega a evaluarse la policy — falla antes, en el privilegio (punto 6b de
-- `db-schema`: una tabla nueva nace sin permisos y solo se concede lo que alguien use).
alter table public.connect_tag_lookups enable row level security;

-- =================================================================================================
-- 3) El incremento, en UNA sentencia
-- =================================================================================================
-- PostgREST no admite expresiones en un UPDATE, así que `lookup_count = lookup_count + 1` no se
-- puede escribir desde la Edge Function, y leer-modificar-escribir es una carrera. Este contador
-- **no se puede recalcular** —no se deriva de ninguna tabla— así que el incremento tiene que ser
-- atómico (punto 9b de `db-schema`): el `on conflict do update` lee y escribe dentro de la misma
-- sentencia, sin ventana en la que dos peticiones se pisen.
--
-- `security definer` porque la tabla no tiene grants para nadie y `service_role` tiene BYPASSRLS
-- pero NO BYPASSGRANT (punto 12 de `rls-security`).
create or replace function public.bump_tag_lookup(p_user_id uuid)
returns int
language sql
volatile
security definer
set search_path = ''
as $$
  insert into public.connect_tag_lookups (user_id, looked_on, lookup_count)
  values (p_user_id, current_date, 1)
  on conflict (user_id, looked_on)
  do update set lookup_count = public.connect_tag_lookups.lookup_count + 1
  returning lookup_count;
$$;

comment on function public.bump_tag_lookup(uuid) is
  'ADR 0028: suma 1 al contador de busquedas por tag de hoy y devuelve el total ya contando la '
  'actual. Una sola sentencia para que el incremento sea atomico. Quien llama incrementa PRIMERO y '
  'decide despues con el valor devuelto: al reves hay una ventana en la que dos peticiones leen el '
  'mismo numero y las dos pasan.';

-- Punto 11 de `db-schema`: cualquier función de `public` es un RPC de PostgREST salvo que se
-- revoque. Sin este `revoke`, cualquier usuario registrado podría llamarla con el uuid de otra
-- persona y gastarle el cupo — un ataque de denegación de servicio dirigido, y contra la única
-- forma que hay de encontrar a alguien a propósito.
revoke execute on function public.bump_tag_lookup(uuid) from public, anon, authenticated;
grant  execute on function public.bump_tag_lookup(uuid) to service_role;

-- =================================================================================================
-- 4) La purga — la tabla nueva entra en el cron que ya existe
-- =================================================================================================
-- Sin esto, `connect_tag_lookups` crecería para siempre: una fila por usuario y día. La función se
-- reemplaza entera (`create or replace`) en vez de crear un segundo cron, porque el test de
-- `connect-purge.sql` ejecuta **el comando literal guardado en `cron.job.command`** — un cron nuevo
-- que nadie ejecutara en el test sería exactamente el fallo silencioso que ese test existe para
-- detectar.
create or replace function private.purge_connect_tables()
returns text
language plpgsql
set search_path = ''
as $$
declare
  v_impressions int;
  v_runs        int;
  v_lookups     int;
begin
  delete from public.connect_impressions where shown_on < current_date - 7;
  get diagnostics v_impressions = row_count;

  delete from public.connect_feed_runs where ran_on < current_date - 7;
  get diagnostics v_runs = row_count;

  delete from public.connect_tag_lookups where looked_on < current_date - 7;
  get diagnostics v_lookups = row_count;

  -- `connect_dismissals` NO se purga: RN-48 dice que un "No mostrar mas" no caduca nunca.
  return format(
    'connect purge: %s impressions, %s feed_runs, %s tag_lookups',
    v_impressions, v_runs, v_lookups
  );
end;
$$;

revoke all on function private.purge_connect_tables() from public, anon, authenticated, service_role;

-- =================================================================================================
-- VERIFICACIÓN
-- =================================================================================================
--   -- 1) Sube de verdad, y la segunda devuelve 2 (no 1 dos veces):
--   select public.bump_tag_lookup('<uuid>');  -- 1
--   select public.bump_tag_lookup('<uuid>');  -- 2
--
--   -- 2) El estado real de los privilegios, que no se deduce leyendo esta migración:
--   select grantee, privilege_type from information_schema.routine_privileges
--    where routine_name = 'bump_tag_lookup';

-- =================================================================================================
-- ROLLBACK:
-- =================================================================================================
-- drop function if exists public.bump_tag_lookup(uuid);
-- drop table if exists public.connect_tag_lookups;
-- -- y restaurar `private.purge_connect_tables()` a su versión de `20260823120400_connect.sql`.
