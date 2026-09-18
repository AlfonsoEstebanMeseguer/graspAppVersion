import '../../domain/rooms/room_summary.dart';

/// Mapea la respuesta de `rooms-feed` a la lista de salas.
///
/// Vive fuera del repositorio para poder probarse sin `SupabaseClient`, sin sesión y sin red —
/// igual que `mapProfileRows` (`data/profile/profile_mapper.dart`).
///
/// Una fila que no sea un mapa se salta en vez de tumbar la lista: la respuesta viene de un
/// `jsonDecode`, y perder una sala es mejor que perder la pantalla.
List<RoomSummary> mapRoomsFeed(Map<String, dynamic> body) {
  final Object? rooms = body['rooms'];
  if (rooms is! List) return const <RoomSummary>[];

  return <RoomSummary>[
    for (final Object? row in rooms)
      if (row is Map) RoomSummary.fromJson(Map<String, dynamic>.from(row)),
  ];
}

/// Mapea el catálogo de temas de `onboarding-catalogs`.
///
/// ## El filtro `id is String` no es defensa genérica: es el caso que va a ocurrir
///
/// La versión desplegada en producción de `onboarding-catalogs` (v9, 2026-08-13) **no manda el
/// `id`** — se añadió el 2026-09-02 y el redespliegue va con el cierre de fase. Contra esa versión
/// esta función devuelve **lista vacía**, no una lista de categorías sin identificador con las que
/// después se pediría un feed filtrado por `null`.
///
/// Y lista vacía es exactamente lo que la pantalla necesita para degradar con dignidad: sin
/// catálogo no pinta la fila de chips, porque unos chips que no pueden filtrar afirmarían que se
/// puede filtrar.
List<RoomCategory> mapRoomCategories(Map<String, dynamic> body) {
  final Object? raw = body['categories'];
  if (raw is! List) return const <RoomCategory>[];

  return <RoomCategory>[
    for (final Object? item in raw)
      if (item is Map && item['id'] is String && item['name'] is String)
        RoomCategory(id: item['id'] as String, name: item['name'] as String),
  ];
}
