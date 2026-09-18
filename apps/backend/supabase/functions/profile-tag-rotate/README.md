# profile-tag-rotate

Trigger: HTTP (app). Rota el tag público del usuario (`§6.2` de
`docs/spec-contactos-mensajes-conectar.md`), con un tope de **1 cada 24 h**.

Input: ninguno. El body se ignora — **no hay nada que elegir**, y ése es el punto.

Output (200): `{ success, tag, next_rotation_at }`.

## «Inmutable» y «puede solicitar un nuevo tag» no se contradicen

El `§1` de la spec dice que el tag es *inmutable* y el `§6.2` que se puede *solicitar uno nuevo*. Se
resuelve leyendo bien la primera: **inmutable significa que el usuario no lo ELIGE**, no que no se pueda
cambiar. Esta función lo cambia; lo que nadie puede hacer es decidir cuál sale.

**Y esa garantía no vive en este código.** Vive en que `authenticated` **no tiene `grant update` sobre
`profiles.tag`** y no lo tendrá nunca (migración `20260823120000`; el caso 6 de
`apps/backend/supabase/tests/signup-validation.sql` lo fija con un test). Por eso esta función usa
`service_role`: es el único camino por el que esa columna se puede escribir. Si la comprobación estuviera
solo aquí, bastaría un `PATCH` directo a PostgREST para elegirse el tag a mano.

El valor lo acuña `public.mint_user_tag` **dentro de la base de datos**, que es también quien reintenta
contra el índice único. Esta función no construye ningún tag.

## El tope de 24 h se consume ANTES de rotar, y es deliberado

Son dos escrituras en dos tablas sin una transacción que las una, así que hay que elegir qué se rompe si
falla la segunda:

- Rotar primero y marcar después → si falla el marcado, **el tope no existe**: se puede rotar en bucle,
  invalidando cada vez el tag que los contactos habían guardado.
- Marcar primero y rotar después → si falla la rotación, se gasta un cupo sin cambiar nada. Molesto y raro;
  se espera 24 h.

Se elige la segunda: **falla cerrado**. Además, la condición del cupo va **dentro del propio `UPDATE`**
(`tag_rotated_at is null or tag_rotated_at <= now() - 24h`), que hace de cerrojo: dos peticiones
simultáneas pasan las dos la comprobación previa, pero solo una encuentra fila que actualizar. Sin eso, el
tope se salta con dos pulsaciones rápidas.

Al superarlo devuelve **422** con el límite concreto y el instante exacto en que se recupera (`RN-21`:
nunca un fallo mudo ni un genérico).

## Verificado de punta a punta

Contra el stack local, con un alta real: primera llamada `200` con tag nuevo, segunda inmediata `422` con
`retry_at`, sin JWT `401`, `GET` `405`, y la base con el tag rotado y el cupo consumido. La lógica del tope
es pura y vive en `_shared/tag-rotate.ts` con sus 12 tests, incluido el borde de las 24 h **en punto** —
donde sí hay cupo, que es el off-by-one clásico.

## Lo que esta función NO hace

- **No valida ningún input**, porque no recibe ninguno. Si algún día acepta un tag propuesto, deja de ser
  esta función.
- **No avisa a nadie de que el tag cambió.** Quien tuviera guardado el anterior deja de encontrarte, y no
  hay notificación ni historial de tags. Es la razón de que exista el tope.
