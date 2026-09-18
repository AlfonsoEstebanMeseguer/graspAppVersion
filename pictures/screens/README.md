# pictures/screens — bocetos de referencia

`frontend-agent` debe visualizar (`view`) el boceto correspondiente **antes** de maquetar cualquier pantalla
(Sección 5.2 del documento maestro).

## Bocetos disponibles (formato `.jpeg`)

| Fichero | Pantalla |
|---|---|
| `01-Start_Menu.jpeg` | Bienvenida / entrada a la app |
| `02-onboarding-questions.jpeg` | Cuestionario del feed personalizado |
| `04-room-active.jpeg` | Sala de voz activa |
| `05-private-call.jpeg` | Llamada privada 1:1 |
| `06-messaging-inbox.jpeg` | Bandeja de mensajería directa |
| `07-gift-catalog.jpeg` | Catálogo de gifts |
| `08-profile.jpeg` | Perfil de usuario |
| `09-Searching-rooms.jpeg` | Salas de voz. ⚠️ **Parcialmente superado** por el [ADR 0032](../../docs/decisions/0032-el-feed-de-salas-no-se-personaliza.md) — ver abajo |
| `10-reports.jpeg` | Métricas de usuario (tiempo en salas, salas accedidas, etc.) |

## Pantallas sin boceto propio — derivaciones acordadas

Si una pantalla no tiene boceto, **no se improvisa**: se aplica la derivación de esta tabla. Si la pantalla no
aparece aquí tampoco, se pregunta al usuario antes de maquetar.

| Pantalla | Se deriva de |
|---|---|
| Login | `01-Start_Menu.jpeg` |
| Registro | `01-Start_Menu.jpeg` |
| Verificación OTP | `01-Start_Menu.jpeg` |
| Chat de una conversación | `06-messaging-inbox.jpeg` |
| Paywall VIP | `07-gift-catalog.jpeg` |
| Edición del feed desde perfil | `02-onboarding-questions.jpeg` + `08-profile.jpeg` |
| Reporte de moderación | `08-profile.jpeg` |
| **Conectar** | Ya implementada — **la pantalla es su propia referencia** (2026-08-31, ver abajo) |
| **Mensajes** (bandeja de 2 pestañas) | `06-messaging-inbox.jpeg` — *acordado el 2026-08-23* |
| **Listas de seguidores / seguidos / solicitudes** | `08-profile.jpeg` — *acordado el 2026-08-23* |
| **Ajustes** (y su sección Apariencia) | `08-profile.jpeg` — *acordado el 2026-08-30* |

### Detalle de las tres derivaciones de la Fase 4 (2026-08-23)

- **Conectar.** ⚠️ **Su boceto `03-feed-rooms.jpeg` se borró el 2026-08-31** y no se restaura: se decidió
  que no habrá feed de salas, y el fichero llevaba ese nombre pese a ser el de la antigua segunda pestaña
  inerte que Conectar sustituyó. **La pantalla ya está implementada**, así que la referencia viva es el
  código —[`connect_screen.dart`](../../apps/mobile/lib/features/connect/presentation/connect_screen.dart)
  y sus widgets—, no una imagen. La estructura que fijaba el §6.1 de la spec sigue en pie: buscador
  arriba, fila horizontal de píldoras, lista vertical de tarjetas. La tarjeta sigue el layout del §6.4:
  foto + punto de actividad a la izquierda, nombre · edad · bio a 2 líneas · chips no interactivos en el
  centro, botón de chat coloreado a la derecha, y el `✕` «No mostrar más» en la esquina.
  ⚠️ Los chips **no llevan intereses ni categorías**, por muy «de intereses» que los llame el boceto: son
  dato del Art. 9 RGPD. Llevan las cuatro señales no sensibles del
  [ADR 0020](../../docs/decisions/0020-conectar-no-muestra-datos-del-articulo-9.md).
- **Mensajes ← `06-messaging-inbox.jpeg`.** Sus dos píldoras superiores «Todos / En el escenario» pasan a
  ser **«Contactos / Solicitudes»**, con el contador `(N)` visible solo si `N > 0` (§8.1). El resto de la
  fila —foto, nombre, último mensaje a 1 línea, hora— se mantiene tal cual. Las filas de **Solicitudes no
  pintan punto de actividad** (`RN-30`).
- **Listas de seguidores/seguidos/solicitudes ← `08-profile.jpeg`.** Se sigue el patrón que ya usa
  `ProfileBadgesModal` sobre ese mismo boceto: cabecera centrada, tarjetas blancas de radio ~20 y filas con
  foto + nombre + tag. Las acciones (`Aceptar`/`Rechazar`, dejar de seguir, quitar seguidor) van al final
  de la fila.

### Ajustes ← `08-profile.jpeg` (2026-08-30)

Se entra desde el engranaje del propio perfil, así que hereda su lenguaje: cabecera centrada, fondo
`canvas` y tarjetas de sección con el mismo radio (~20) y la misma sombra suave que «Insignias» y
«Estadísticas». Se apila por encima de la barra inferior (`rootNavigator: true`), como las listas de
seguidores: es un sitio del que se vuelve, no una quinta pestaña.

## Bocetos parcialmente superados

Un boceto superado **no se borra ni se sustituye**: se anota aquí qué parte suya dejó de ser cierta y por
qué decisión. Todo lo que no aparezca en la lista sigue siendo la referencia buena.

### `09-Searching-rooms.jpeg` — [ADR 0032](../../docs/decisions/0032-el-feed-de-salas-no-se-personaliza.md) (2026-08-31)

Sigue valiendo como referencia de **lenguaje visual** (tarjetas, aire, cabecera, píldora de acción). Deja
de valer en la **estructura**, porque el feed de salas ya no se personaliza:

| El boceto pinta | Y ahora es |
|---|---|
| Tarjeta grande de «Sala Destacada» arriba | **No hay sala destacada.** Una sola lista |
| Encabezado «Salas recomendadas para ti» + «Ver todas» | **No hay recomendación ni personalización.** La lista es la misma para todo el mundo, ordenada por actividad reciente |
| Ninguna fila de filtros | **Fila de chips de categoría** (`Todas` + categorías de experiencia), con el patrón de Conectar |
| Foto pequeña del creador a la izquierda de cada tarjeta | La foto del creador **en grande** a la izquierda |
| Solo el tema en el título | **Título** (texto libre) **y tema** (chip de categoría, de catálogo) |
| «18 en la sala» en texto | **Cadena de hasta 4 avatares** abajo a la derecha (escenario primero, luego los últimos en entrar, sin repetir al creador) y burbuja **`+N`** con los que no caben — `+N`, no el total |

### `04-room-active.jpeg` — spec de Fase 5 (2026-08-31)

**Su estructura vale entera** y es la referencia para maquetar la sala. Dos matices:

- Los números son ilustrativos: pinta «24 oyentes» y «Oyentes (21)», y el **aforo decidido es 20**. No
  se «corrige» el aforo citando la imagen.
- De la barra inferior, **`Silenciar` es de la Fase 6** y no se pinta hasta que haya audio — ni siquiera
  deshabilitado. `Chat`, `Pedir la palabra` y `Más` sí son de la Fase 5.

Detalle en la [spec de Fase 5](../../docs/superpowers/specs/2026-08-31-salas-de-voz-fase5-design.md) § 6.2.

## Lenguaje visual común

Extraído de los bocetos, aplicable a toda pantalla nueva:

> ⚠️ **Los bocetos son el tema CLARO.** Desde el
> [ADR 0031](../../docs/decisions/0031-modo-oscuro-con-paleta-por-rol.md) la app tiene también tema
> oscuro, y no hay bocetos de él: lo que cambia es el color, nunca el layout. Al maquetar se consumen
> **roles** (`context.palette.canvas`, `.surface`, `.brand`…), no los hexadecimales de esta lista —
> escribirlos a pelo deja la pantalla en claro dentro de la app en oscuro.

- Fondo general: rol `canvas` — `purple-50` (`#F5F2FA`) en claro, `#14101F` en oscuro.
- Tarjetas: rol `surface` — blancas en claro, `#221B33` en oscuro. Radio ~20, sombra muy suave y difusa
  (nunca borde duro).
- CTAs y píldoras: rol `brand` — `purple-500` (`#8B5CF6`) en claro, `#A78BFA` en oscuro. Radio completo.
- Cabeceras centradas, títulos en Poppins, cuerpo en Inter.
- Mucho aire entre bloques; ilustraciones acuareladas en púrpura como fondo decorativo.
