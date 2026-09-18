# messaging-inbox

Trigger: HTTP (app), `GET /functions/v1/messaging-inbox`. Las dos bandejas del §8 —`Contactos` y
`Solicitudes`— proyectadas **por espectador**. Fase 4, Tarea 11.

Requiere `service_role`: **sí**. `conversations` no tiene ni un `grant` para `authenticated`, así
que no hay consulta de cliente capaz de leer `status` ni `initiator_id` (RN-06).

## Lo que decide qué ve cada uno vive en `_shared/messaging-view.ts`

Aquí solo se cargan filas y se decoran. La proyección es pura y tiene 30 tests, con las seis
mutaciones comprobadas. Reparto:

| Regla | Dónde se cumple |
|---|---|
| RN-02 · mi solicitud enviada va a **mis** Contactos | `bucketFor` |
| RN-03 · la recibida va a Solicitudes, nunca a Contactos | `bucketFor` |
| RN-06 · una `ignored` se ve igual que una `pending` para quien la inició, y **no existe** para el receptor | `bucketFor` + `pending_acceptance` |
| RN-22 / RN-27 · lo archivado no se lista | `bucketFor` (y el `.eq("hidden", false)` de la consulta) |
| RN-27 / RN-28 · el último mensaje respeta `cleared_at` y `deleted_for` | `visibleLastMessage` |
| RN-29 · orden por `last_message_at desc` | `projectInbox` |
| RN-31 · `unread_count` es el **propio**; `status` e `initiator_id` no se emiten | los tipos de salida |
| RN-30 · el punto de actividad **no** aparece en Solicitudes | este handler, y solo para `contacts` |

## `service_role` se salta la RLS, y eso tiene consecuencias aquí

La policy `direct_messages_read_participant` aplica `deleted_for` (RN-28) y `cleared_at` (RN-27)
**para el cliente**. Esta función no pasa por ella. Por eso el último mensaje no se pinta tal y como
viene de la tabla: se pasa por `visibleLastMessage`, que reimplementa las dos reglas una sola vez y
con tests, en vez de dos veces a mano en dos handlers.

## La trampa de `activity_status`, que no da error

`activity_status` **se llama con el cliente del usuario, nunca con el de servicio.** La función
deriva quién pregunta de `auth.uid()`, y con la clave de servicio eso es `NULL`.

Comprobado contra la base, no deducido: con un token sin `sub` devuelve `false` para un usuario que
está activo en ese momento; con el `sub` del usuario devuelve `true`. Es decir, llamarla con
`service` **no falla** — pinta todos los puntos en gris, en silencio y para siempre.

Y hay una segunda razón, de regla y no de fontanería: RN-32 es recíproco —quien oculta su actividad
no ve la de nadie— y eso se resuelve mirando al llamante. Sin identidad no hay forma de aplicarlo.

Verificado en vivo: `is_active: true` con el otro activo, y `false` en cuanto el propio espectador
pone `hide_activity_status`.

> La migración `20260823120300` concede `execute` a `service_role` sobre esta función con un
> comentario que decía que era para que la bandeja resolviera el punto server-side. Ese comentario
> se ha corregido: el grant se queda (no estorba y algún día puede hacer falta), pero usarlo así
> rompe RN-30 y RN-32 sin un solo error.

## El último mensaje, en una sola consulta

PostgREST no sabe hacer «el más reciente por grupo», y una consulta por conversación sería N+1 en la
pantalla más visitada de la app. Se aprovecha que `conversations.last_message_at` ya guarda el
instante exacto del último mensaje de cada hilo: se piden los mensajes por
`conversation_id in (...)` **y** `created_at in (esos instantes)`, y se descarta lo que no case con
su propio hilo. Una consulta, acotada.

## Salida

```jsonc
{
  "contacts": [{
    "conversation_id": "<uuid>", "other_user_id": "<uuid>",
    "display_name": "Ana", "preset_avatar": null,
    "last_message_at": "…", "unread_count": 0, "pending_acceptance": true,
    "last_message": { "content": "Hola", "from_me": true, "created_at": "…", "deleted_for_all": false },
    "is_active": false
  }],
  "requests": [ /* igual, pero SIN `is_active` — RN-30 */ ],
  "requests_count": 1
}
```

La **foto no viaja**: se pide aparte a `profile-photo-view-url`, que es quien firma su URL contra R2.
`display_name` y `preset_avatar` sí, porque ya son legibles por `authenticated` vía PostgREST — no se
expone nada nuevo, se ahorra una tanda de peticiones.

Tope de 100 conversaciones por bandeja: `activity_status` **lanza excepción** por encima de 500 ids,
y la bandeja le pasa uno por contacto.

## Verificado de punta a punta en local (2026-08-25)

- emisora → Contactos con `pending_acceptance: true`; receptor → Solicitudes, **sin la clave
  `is_active`** siquiera (RN-30);
- tras ignorar, la bandeja de la emisora es **byte a byte idéntica** a la de antes, y la del receptor
  queda vacía (RN-06);
- `is_active` responde de verdad (`true` con el otro activo, `false` al ocultar la propia actividad).

Estado: **implementado, sin desplegar.**
