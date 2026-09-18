import 'package:grasp_mobile/domain/rooms/room_summary.dart';
import 'package:grasp_mobile/domain/rooms/rooms_repository.dart';

/// Doble de [RoomsRepository] que además **anota con qué categoría se le pidió el feed**.
///
/// Eso es lo que permite probar el filtro de verdad: comprobar que la lista cambia no distingue un
/// filtro que funciona de una pantalla que filtra en el cliente, y este último sería exactamente el
/// error del ADR 0032 (una segunda fuente de verdad para lo que decide `rooms_feed`).
class FakeRoomsRepository implements RoomsRepository {
  FakeRoomsRepository({
    this.rooms = const <RoomSummary>[],
    this.categoryList = const <RoomCategory>[],
    this.byCategory = const <String, List<RoomSummary>>{},
    this.categoriesThrow = false,
  });

  List<RoomSummary> rooms;
  List<RoomCategory> categoryList;

  /// Qué devolver cuando se filtra. Lo que no esté aquí devuelve lista vacía.
  Map<String, List<RoomSummary>> byCategory;

  bool categoriesThrow;

  /// Un elemento por llamada, con el `categoryId` pedido (`null` = `Todas`).
  final List<String?> feedCalls = <String?>[];
  int categoryCalls = 0;

  @override
  Future<List<RoomSummary>> feed({String? categoryId}) async {
    feedCalls.add(categoryId);
    if (categoryId == null) return rooms;
    return byCategory[categoryId] ?? const <RoomSummary>[];
  }

  @override
  Future<List<RoomCategory>> categories() async {
    categoryCalls++;
    if (categoriesThrow) throw Exception('sin catálogo');
    return categoryList;
  }
}

/// Una sala con valores por defecto sensatos; cada test nombra solo lo que le importa.
RoomSummary fakeRoom({
  String id = 'r1',
  String title = 'Hablemos de ansiedad',
  String categoryId = 'cat-1',
  String hostId = 'host-1',
  String? hostName = 'Ana',
  String? hostPhotoPath,
  int occupants = 1,
  List<String>? avatars,
  int? overflow,
}) => RoomSummary(
  id: id,
  title: title,
  categoryId: categoryId,
  hostId: hostId,
  hostName: hostName,
  hostPhotoPath: hostPhotoPath,
  occupants: occupants,
  avatars: avatars ?? const <String>[],
  overflow: overflow ?? 0,
);
