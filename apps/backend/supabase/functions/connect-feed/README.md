# connect-feed

Trigger: HTTP (app), `POST /functions/v1/connect-feed`. El feed de perfiles recomendados de Conectar
(§6, §7). Fase 4, Tarea 16.

Requiere `service_role`: **sí**. Lee `profiles_private`, `onboarding_responses` y `user_experiences`
de **otras** personas —los tres son read-own para el cliente— y escribe `connect_impressions`, que no
tiene ningún grant para `authenticated`.

**Sustituye a `match-feed`**, que la Tarea 0 retiró (decisión 7 del plan): aquel declaraba «salas
**y** perfiles». Las salas serán `rooms-feed`, en la Fase 5.

## Esta función es la frontera del Art. 9 RGPD

Los tres ejes con los que puntúa son el **mismo catálogo de salud mental**: `onboarding_responses`,
`user_experiences` y `profiles_private.primary_category_id`/`secondary_categories` («Ansiedad y
estrés», «Duelo», «He perdido a alguien»). Son categoría especial del Art. 9 y hoy están cerrados
incluso al propio usuario.

Entran aquí, se convierten en **un número** dentro de `_shared/connect-scoring.ts`, y el número solo
sirve para muestrear. **Ni un slug, ni un id de categoría, ni el desglose por eje salen en la
respuesta** — el desglose diría *qué* eje coincidió, que es la categoría dicha de otra forma.

Lo que sí viaja son las señales **no sensibles** de la decisión 1 del plan:

| Campo | Origen | Por qué es seguro |
|---|---|---|
| `listener_profile` | `onboarding_responses.responses.profile` | Preferencia de **estilo** («empático y cercano»), no una condición |
| `time_helping_seconds` | `profiles` | Ya es público |
| `streak_days` | `profiles` | Ya es público |
| `age` | derivado de `profiles_private.birth_date` | La edad sola no es dato del Art. 9 |

**La lista de campos de la respuesta es la frontera**: lo que no esté ahí, no sale. Si un día esta
respuesta devuelve una categoría de otra persona, está mal.
[ADR 0020](../../../../../docs/decisions/0020-conectar-no-muestra-datos-del-articulo-9.md).

## `birth_date`, y ya no hay ninguna `profiles_private.age`

`birth_date` es la única fuente de verdad de la edad. Hasta el 2026-08-27 existía además una
columna `profiles_private.age` que **no escribía nadie** y que estaba a `NULL` en todas las filas:
usarla habría dejado `M_edad` valiendo 1.0 para todo el mundo, en silencio y para siempre — un
multiplicador roto y uno correcto son el mismo número. La Tarea 24 la borró al hacer pública la
edad ([ADR 0026](../../../../../docs/decisions/0026-la-edad-es-publica.md)), porque a un dato que no
lee nadie no se le busca mejor escondite.

**Este cálculo sigue viviendo aquí, en Deno, y tiene un espejo en SQL**: `public.age_in_years()`,
que es lo que usa la vista `public_profiles` para el perfil ajeno. Los dos números se pintan en
pantallas contiguas —la tarjeta de Conectar y el perfil que se abre desde esa misma tarjeta—, así
que **tienen que coincidir**, y por eso los dos calculan en UTC. Si se toca uno, se toca el otro.

## Contrato

**Body** (todo opcional): `{ filters?: string[], refresh?: boolean }`

`filters` acepta `age`, `interests`, `suffered`, `current` (los chips del §6.3). `Todos` es **no
mandar ninguno** (RN-35/RN-36); se acepta también el valor literal `all`, que se ignora.

**Respuesta 200**: `{ candidates: [...], empty_state: boolean, relaxed: boolean }`

- `relaxed: true` — RN-49: había menos de 20 elegibles, así que la tanda se puntuó **sin el cuadrado
  del filtro**. No es un error.
- `empty_state: true` — RN-49: no queda nadie. Nunca una lista vacía sin explicación.

**Errores**: `422 refresh_limit_reached` (RN-46, con `limit` y `retry_at`) · `400 invalid_input` ·
`405` · `401`.

## POST y no GET

Cada llamada **escribe**: `connect_impressions` siempre, y `connect_feed_runs` en un refresco. Un GET
que muta se cachea en cualquier proxy y devuelve la tanda de ayer.

## El contador de refrescos se incrementa ANTES de decidir

RN-46 son 5 `pull-to-refresh` al día. El incremento va en el RPC `bump_connect_refresh`
(migración `20260825130000`), que hace el `insert … on conflict do update … + 1` en **una sola
sentencia**: PostgREST no admite `col = col + 1` y leer-modificar-escribir es una carrera. Es el
mismo muro que la Tarea 10 encontró con `unread_count`, y tampoco aquí se puede recalcular, porque
el contador no se deriva de ninguna tabla.

**Se incrementa primero y se decide después, con el valor devuelto.** Al revés vuelve a abrir la
carrera. Un intento rechazado deja el contador subido, y es correcto: la fecha va en la clave, así
que se reinicia solo cada día (00:00 **UTC** — la base corre en UTC, comprobado).

## Las exclusiones se aplican dos veces, a propósito

Una en el handler, para no cargar los datos del Art. 9 de gente que no puede salir; otra dentro de
`selectConnectBatch`, que es la autoritativa. Filtrar aquí y pasar conjuntos vacíos ahorraría un
recorrido y abriría el agujero que RN-49 cierra: **relajar el filtro no relaja las exclusiones**.
Aplicarlas dos veces es idempotente y cuesta nada.

Son siete: las seis de RN-47 más `shownToday` (RN-46), que además es lo que **pagina** el scroll
infinito. Esa séptima **caduca a medianoche** y las de RN-48 no, por eso no comparten conjunto.

## `activity_status` se llama con el cliente del usuario

Deriva quién pregunta de `auth.uid()`, que con la clave de servicio es `NULL`: devolvería `false`
para todo el mundo **sin dar error**, y todos los puntos saldrían en gris en silencio y para
siempre. Además RN-32 es recíproco —quien oculta su actividad no ve la de nadie— y eso solo se
resuelve sabiendo quién llama. Precedente: skill `edge-functions`, punto 11.

## Limitación conocida: el pool está acotado a 1000 — pero ya no sesga (2026-08-30)

El pool sale del RPC `public.connect_eligible_sample(p_viewer, p_limit)` (migración
`20260830120000`), que devuelve una muestra **aleatoria** de `profiles` con las **siete exclusiones ya
aplicadas en SQL**. Hasta esa fecha era un `limit` sobre la tabla sin ordenar y las exclusiones se
aplicaban después en memoria: de ahí salían el sesgo hacia quien estuviera antes en el índice —la
muestra era siempre la misma— y un `empty_state` posible teniendo candidatos, porque las mil filas
eran perfiles **crudos**.

**Lo que sigue en pie** es el tope de `MAX_POOL = 1000`: alguien con score alto puede quedar fuera de
la tanda por no haber entrado en la muestra. Pasaba antes también; la diferencia es que antes le
pasaba **siempre a las mismas personas**. Anotado en
[`docs/pending-messaging.md`](../../../../../docs/pending-messaging.md) punto 16, en vez de fingir que
el límite no existe.

La función tiene el `execute` **revocado a `authenticated` y `anon`**: recibe al espectador por
parámetro —no de `auth.uid()`, porque con `service_role` eso devuelve la respuesta del anónimo sin dar
error—, así que sin el `revoke` cualquiera podría llamarla con el uuid de otra persona.

## Verificado en vivo (2026-08-25)

Contra el stack local, con tres altas reales: la respuesta trae exactamente los 11 campos seguros y
ninguno de los tres ejes; RN-46 deja la segunda llamada del día en `empty_state`; el bloqueo excluye
**en las dos direcciones** (el bloqueado tampoco ve al bloqueador); el sexto refresco devuelve 422
con su `retry_at`; y el sesgo del scoring se comprobó provocándolo —con el espectador a 1 año del
candidato B y a 36 de C, B salió primero 20 de 24 veces (≈0.83, incompatible con el 0.50 que daría
un espectador sin ejes leídos).
