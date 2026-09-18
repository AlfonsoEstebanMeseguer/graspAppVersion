import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/supabase/supabase_providers.dart';
import '../../../domain/rooms/room_summary.dart';

/// La lista de salas tal y como se pinta.
@immutable
class RoomsFeedView {
  const RoomsFeedView({
    required this.rooms,
    this.categories = const <RoomCategory>[],
    this.selectedCategoryId,
    this.photoUrls = const <String, String>{},
  });

  /// En el orden que decidió `rooms_feed` (actividad reciente, ADR 0032). **No se reordena aquí.**
  final List<RoomSummary> rooms;

  /// El catálogo para los chips. **Vacío significa que no se pudo cargar**, y entonces la pantalla
  /// no pinta la fila: unos chips que no se pueden usar afirmarían que se puede filtrar.
  final List<RoomCategory> categories;

  /// `null` = `Todas`, igual que el conjunto vacío en los chips de Conectar.
  final String? selectedCategoryId;

  /// URLs firmadas por `user_id`, pedidas **de una sola vez** para toda la página. Caducan a los
  /// 300 s; quien las use no las guarda más allá de esta vista.
  final Map<String, String> photoUrls;
}

/// Carga la lista de salas y su catálogo de temas (§6.1 de la spec de la Fase 5).
///
/// ## Una sola llamada de firmas por página, no una por tarjeta
///
/// Cada tarjeta necesita la foto del host y hasta 4 caras más: pedirlas por tarjeta serían 5N
/// peticiones para pintar una pantalla. `profile-photo-view-url` acepta `user_ids` como array desde
/// el primer día, así que se junta todo —hosts con foto y toda la cadena de avatares— en **una**
/// llamada por carga, igual que hacen la bandeja y Conectar.
///
/// De los hosts solo se piden los que tienen `hostPhotoPath`: sin él no hay foto que firmar. De la
/// cadena se piden todos, porque `rooms-feed` manda `user_id` a secas y no dice quién tiene foto —
/// los que no la tengan sencillamente no salen del mapa.
class RoomsController extends AutoDisposeAsyncNotifier<RoomsFeedView> {
  String? _categoryId;

  /// El catálogo se pide una vez por sesión de pantalla: es de catálogo cerrado y no cambia entre
  /// un filtro y el siguiente.
  List<RoomCategory>? _categories;

  @override
  Future<RoomsFeedView> build() => _fetch();

  /// Cambia el chip activo y vuelve a pedir la lista. `null` = `Todas`.
  Future<void> selectCategory(String? categoryId) async {
    if (_categoryId == categoryId) return;
    _categoryId = categoryId;
    // `copyWithPrevious`: la lista anterior sigue en pantalla mientras llega la nueva. Vaciarla
    // haría desaparecer la fila de chips —vive en la misma vista— y el usuario perdería de vista el
    // control que acaba de tocar.
    state = const AsyncValue<RoomsFeedView>.loading().copyWithPrevious(state);
    state = await AsyncValue.guard(_fetch);
  }

  /// `Pull-to-refresh`. Reemplaza la lista conservando el filtro.
  Future<void> refresh() async {
    state = await AsyncValue.guard(_fetch);
  }

  Future<RoomsFeedView> _fetch() async {
    final List<RoomCategory> categories = _categories ??= await _categoriesOrEmpty();
    final List<RoomSummary> rooms = await ref
        .read(roomsRepositoryProvider)
        .feed(categoryId: _categoryId);

    return RoomsFeedView(
      rooms: rooms,
      categories: categories,
      selectedCategoryId: _categoryId,
      photoUrls: await _photoUrls(rooms),
    );
  }

  /// El catálogo no puede tumbar la pantalla: sin chips se sigue viendo la lista entera, que es el
  /// estado por defecto de todas formas.
  Future<List<RoomCategory>> _categoriesOrEmpty() async {
    try {
      return await ref.read(roomsRepositoryProvider).categories();
    } on Object {
      return const <RoomCategory>[];
    }
  }

  Future<Map<String, String>> _photoUrls(List<RoomSummary> rooms) async {
    final Set<String> ids = <String>{
      for (final RoomSummary room in rooms) ...<String>[
        if (room.hostPhotoPath != null) room.hostId,
        ...room.avatars,
      ],
    };
    if (ids.isEmpty) return const <String, String>{};

    try {
      return await ref
          .read(avatarRepositoryProvider)
          .photoUrls(ids.toList(growable: false));
    } on Object {
      // Que no se pueda firmar una foto no puede vaciar la lista: se pintan los marcadores.
      return const <String, String>{};
    }
  }
}

final AutoDisposeAsyncNotifierProvider<RoomsController, RoomsFeedView>
roomsControllerProvider =
    AsyncNotifierProvider.autoDispose<RoomsController, RoomsFeedView>(
      RoomsController.new,
    );
