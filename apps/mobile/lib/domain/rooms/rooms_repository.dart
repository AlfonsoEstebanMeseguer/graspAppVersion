import 'room_summary.dart';

/// Lectura de la lista de salas y de su catálogo de temas.
///
/// Va aparte de la capa social por la misma razón que `AvatarRepository` va aparte de
/// `ProfileRepository`: son superficies distintas. Aquí **solo hay lectura** — toda escritura de
/// estado de una sala (crear, entrar, salir, pedir la palabra) pasa por `room-actions`, que es la
/// única dueña del aforo y del tope de hablantes, y no se mezcla con el feed para que no exista la
/// tentación de decidir en el cliente quién cabe.
abstract interface class RoomsRepository {
  /// Las salas `live`, ordenadas por actividad reciente (ADR 0032). Con [categoryId] filtra por
  /// tema; sin él, todas.
  ///
  /// El orden lo decide `rooms_feed` en Postgres y **no se reordena en el cliente**: dos fuentes de
  /// verdad para el mismo orden es exactamente lo que el ADR evita.
  Future<List<RoomSummary>> feed({String? categoryId});

  /// El catálogo de temas para la fila de chips.
  Future<List<RoomCategory>> categories();
}
