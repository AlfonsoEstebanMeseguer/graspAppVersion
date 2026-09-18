-- 20260830120000 — El feed de Conectar deja de muestrear las 1000 primeras filas.
--
-- QUÉ ARREGLA, Y QUÉ NO ERA EL PROBLEMA
--
-- `connect-feed` traía a memoria `profiles` con `.limit(1000)` SIN filtrar, y aplicaba las
-- exclusiones después. De ahí salían dos síntomas (punto 16 de `docs/pending-messaging.md`):
--
--   · el feed se sesgaba hacia quien estuviera antes en el índice, porque la muestra era siempre
--     LA MISMA — determinista, no aleatoria;
--   · podía responder `empty_state` habiendo candidatos, porque si esas 1000 filas crudas
--     resultaban todas excluidas, nadie miraba más allá.
--
-- Los dos vienen de QUÉ mil filas se eligen y de CUÁNDO se excluye, no de que sean mil. Por eso
-- esta función NO mueve el scoring del §7 a Postgres: ese scoring vive en TypeScript con 42 tests,
-- y duplicarlo aquí sería exactamente lo que prohíbe el punto 4d de `db-schema`.
--
-- POR QUÉ EL ESPECTADOR ENTRA POR PARÁMETRO Y NO POR `auth.uid()`
--
-- Un RPC que se personaliza con `auth.uid()` y se llama con `service_role` devuelve la respuesta
-- del ANÓNIMO y **no da error**: la clave de servicio es un JWT sin `sub` (punto 11 de la skill
-- `edge-functions`, que este proyecto ya pagó una vez con `activity_status`). Con el espectador
-- como argumento esa trampa no existe — y el `revoke` de abajo es lo que impide que el argumento
-- se convierta en un agujero.

create or replace function public.connect_eligible_sample(p_viewer uuid, p_limit int)
returns table (
  user_id              uuid,
  display_name         text,
  tag                  text,
  bio                  text,
  preset_avatar        text,
  photo_path           text,
  time_helping_seconds int,
  streak_days          int
)
language sql
stable
security definer
set search_path = ''
as $$
  select p.user_id, p.display_name, p.tag, p.bio, p.preset_avatar, p.photo_path,
         p.time_helping_seconds, p.streak_days
    from public.profiles p
   where p.user_id <> p_viewer
     -- `tag not null` NO es un filtro de negocio: es cómo se reconoce un perfil ya dado de alta.
     and p.tag is not null
     -- RN-47(2) mitad A: el espectador bloqueó a esta persona.
     and not exists (select 1 from public.blocks b
                      where b.blocker_id = p_viewer and b.blocked_id = p.user_id)
     -- RN-47(2) mitad B: esta persona bloqueó al espectador. ES LA QUE SE OLVIDA — no se ve desde
     -- la propia lista, porque `blocks` solo lo lee su `blocker_id`.
     and not exists (select 1 from public.blocks b
                      where b.blocker_id = p.user_id and b.blocked_id = p_viewer)
     -- RN-47(3): conversación en CUALQUIER estado, `ignored` incluido. RN-47(4) —las solicitudes
     -- pendientes— está contenida aquí: una solicitud ES una conversación.
     and not exists (select 1 from public.conversations c
                      where (c.user_a_id = p_viewer and c.user_b_id = p.user_id)
                         or (c.user_a_id = p.user_id and c.user_b_id = p_viewer))
     -- RN-47(5): a quien ya sigue, en cualquier estado.
     and not exists (select 1 from public.user_follows f
                      where f.follower_id = p_viewer and f.followee_id = p.user_id)
     -- RN-47(6): «No mostrar más». RN-48: no caduca nunca.
     and not exists (select 1 from public.connect_dismissals d
                      where d.user_id = p_viewer and d.dismissed_user_id = p.user_id)
     -- RN-46: ya se le enseñó HOY. Caduca a medianoche porque la fecha va en la PK.
     and not exists (select 1 from public.connect_impressions i
                      where i.user_id = p_viewer and i.shown_user_id = p.user_id
                        and i.shown_on = current_date)
   order by random()
   limit p_limit;
$$;

comment on function public.connect_eligible_sample(uuid, int) is
  'Muestra ALEATORIA de perfiles elegibles para el feed de Conectar, con las siete exclusiones '
  '(RN-47 y RN-46) ya aplicadas. El orden aleatorio es el arreglo del punto 16 de '
  'pending-messaging: con `limit` sobre `profiles` sin ordenar, la muestra era siempre la misma y '
  'sesgaba el feed hacia quien estuviera antes en el indice. NO puntua: el scoring del parrafo 7 '
  'vive en TypeScript y no se duplica aqui.';

-- Punto 11 de db-schema: cualquier función de `public` es un RPC de PostgREST salvo que se revoque.
-- SIN ESTE REVOKE la función es una fuga: recibe el `p_viewer` por parámetro, así que cualquier
-- usuario registrado podría llamarla con el uuid de otra persona y deducir de la respuesta a quién
-- ha bloqueado, con quién habla y a quién ha descartado. Mismo patrón que `bump_connect_refresh`.
revoke execute on function public.connect_eligible_sample(uuid, int) from public, anon, authenticated;
grant  execute on function public.connect_eligible_sample(uuid, int) to service_role;

-- rollback:
-- drop function if exists public.connect_eligible_sample(uuid, int);
