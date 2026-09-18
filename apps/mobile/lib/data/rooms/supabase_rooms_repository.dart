import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/rooms/room_summary.dart';
import '../../domain/rooms/rooms_repository.dart';
import '../social/social_edge_call.dart';
import 'rooms_mapper.dart';

/// [RoomsRepository] sobre las Edge Functions `rooms-feed` y `onboarding-catalogs`.
///
/// ## Por qué el catálogo de temas se pide a `onboarding-catalogs`
///
/// `public.categories` **no tiene `grant` para `authenticated`** (baseline, § grants: «el cliente
/// los lee vía Edge Function con `service_role`, nunca por PostgREST directo, aunque sus policies
/// sean públicas»). El único endpoint que ya publica ese catálogo es `onboarding-catalogs`, así que
/// se reutiliza en vez de estrenar una función que devolvería exactamente lo mismo.
///
/// Lo único que hizo falta es que devuelva el `id` junto al `slug`: `rooms-feed` filtra por uuid
/// (`p_category uuid`) y el slug no sirve para nada aquí. Es un campo **añadido**, no un cambio: el
/// mapper del onboarding ignora las claves que no conoce.
class SupabaseRoomsRepository implements RoomsRepository {
  SupabaseRoomsRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<List<RoomSummary>> feed({String? categoryId}) async {
    final Map<String, dynamic> body = await invokeEdge(
      _client,
      'rooms-feed',
      method: HttpMethod.get,
      // Sin la clave cuando no hay filtro: `rooms-feed` rechaza con 400 cualquier `categoryId` que
      // no sea un uuid, y una cadena vacía viajaría como `categoryId=`.
      query: categoryId == null
          ? null
          : <String, dynamic>{'categoryId': categoryId},
    );

    return mapRoomsFeed(body);
  }

  @override
  Future<List<RoomCategory>> categories() async {
    final Map<String, dynamic> body = await invokeEdge(
      _client,
      'onboarding-catalogs',
      method: HttpMethod.get,
    );

    return mapRoomCategories(body);
  }
}
