# features/rooms

Lista de salas (feed), sala activa, chat de sala, escenario de hablantes/oyentes.
Ver Fase 5 (CRUD + ciclo de vida) y Fase 6 (integración de voz) — Sección 8 del documento maestro.

## Qué hay hoy

- `presentation/rooms_screen.dart` — la lista de salas activas. Sustituyó al placeholder
  «Próximamente» el 2026-09-02 (Fase 5, Tarea 7).
- `presentation/widgets/room_card.dart` — la tarjeta del ADR 0032 § 4: host en grande, título, chip
  de tema y cadena de hasta 4 caras con burbuja `+N`.
- `presentation/widgets/room_category_chips.dart` — la fila de temas, reutilizando el
  `ConnectFilterChip` de Conectar.
- `application/rooms_controller.dart` — carga el feed y **una sola** tanda de URLs firmadas por
  página.

Los datos vienen de `domain/rooms/` + `data/rooms/` (capas del proyecto, no del feature).

Pendiente: la pantalla de sala (Tarea 8) y **crear una sala**, que hoy no tiene formulario en la app
aunque `room-actions` la implemente. Por eso el estado vacío no ofrece ningún botón.

## Bocetos

- `pictures/screens/09-Searching-rooms.jpeg` — la lista. ⚠️ **Parcialmente superado** por el
  [ADR 0032](../../../../docs/decisions/0032-el-feed-de-salas-no-se-personaliza.md): su lenguaje
  visual vale, su estructura no (no hay sala destacada, ni «recomendadas para ti», ni «Ver todas»).
- `pictures/screens/04-room-active.jpeg` — la sala activa. Estructura válida entera, con los dos
  matices del README de `pictures/screens/`.
