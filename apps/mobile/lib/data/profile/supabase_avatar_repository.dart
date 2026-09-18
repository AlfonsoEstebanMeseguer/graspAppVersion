import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/profile/avatar_repository.dart';
import '../../domain/profile/avatar_type.dart';
import 'photo_url_batches.dart';

/// Implementación de [AvatarRepository] sobre las tres Edge Functions de foto de perfil.
///
/// El flujo de subida son **tres pasos y no uno**, y el del medio no pasa por el backend:
///
///   1. `profile-photo-upload-url` firma un `PUT` contra R2 (el servidor elige la clave).
///   2. El cliente sube los bytes **directamente a R2**. El backend no los ve nunca.
///   3. `profile-avatar-set` confirma: descarga el objeto, comprueba que es de verdad una imagen
///      del formato declarado y solo entonces escribe `profiles.photo_path` (decisión 0013).
///
/// Que el paso 2 no pase por el backend es lo que hace barata la subida, y también la razón de que
/// exista el paso 3: **una subida sin confirmar es basura que solo detecta `media-reconcile-cron`**.
class SupabaseAvatarRepository implements AvatarRepository {
  SupabaseAvatarRepository(this._client, {http.Client? httpClient})
    : _http = httpClient ?? http.Client();

  final SupabaseClient _client;

  /// Cliente HTTP para el `PUT` a R2. Va aparte del de Supabase a propósito: esa petición no lleva
  /// JWT ni `apikey`, solo la firma que ya viaja en la URL.
  final http.Client _http;

  @override
  Future<String> uploadPhoto(Uint8List imageBytes, String mimeType) async {
    // Paso 1 — firma. El tamaño y el mime van FIRMADOS, así que tienen que ser los reales.
    final FunctionResponse signed = await _client.functions.invoke(
      'profile-photo-upload-url',
      body: <String, dynamic>{
        'file_size': imageBytes.length,
        'mime_type': mimeType,
      },
    );
    _throwIfError(signed, 'No se pudo preparar la subida de la foto.');

    final Map<String, dynamic> data = _asMap(signed.data);
    final String? uploadUrl = data['upload_url'] as String?;
    final String? path = data['path'] as String?;
    if (uploadUrl == null || path == null) {
      throw const AvatarException(
        'El servidor no devolvió una URL de subida válida.',
      );
    }

    // Paso 2 — los bytes, directos a R2. El `Content-Type` tiene que ser EXACTAMENTE el firmado:
    // R2 compara la firma y devuelve 403 si no coincide, sin decir por qué.
    final http.Response put = await _http.put(
      Uri.parse(uploadUrl),
      headers: <String, String>{'Content-Type': mimeType},
      body: imageBytes,
    );
    if (put.statusCode < 200 || put.statusCode >= 300) {
      throw AvatarException(
        'No se pudo subir la foto (${put.statusCode}). Revisa tu conexión e inténtalo de nuevo.',
      );
    }

    // Paso 3 — confirmar. Aquí es donde el backend mira los bytes.
    final FunctionResponse confirmed = await _client.functions.invoke(
      'profile-avatar-set',
      body: <String, dynamic>{'photo_path': path},
    );
    _throwIfError(confirmed, 'La foto se subió pero no se pudo confirmar.');

    return path;
  }

  @override
  Future<void> setPreset(AvatarType preset) async {
    final FunctionResponse response = await _client.functions.invoke(
      'profile-avatar-set',
      body: <String, dynamic>{'preset': preset.slug},
    );
    _throwIfError(response, 'No se pudo cambiar el avatar.');
  }

  @override
  Future<String?> photoUrl(String userId) async =>
      (await photoUrls(<String>[userId]))[userId];

  /// **Trocea en tandas de [photoUrlsBatchSize]**, que es el tope del endpoint.
  ///
  /// Sin el troceo, una lista larga —la de salas cruza el tope a partir de ~11 salas— recibe un
  /// **400** y el llamante se queda sin **ninguna** foto, no con las que cupieran. Y como el 400
  /// suele atraparse arriba para que una foto no tumbe una pantalla, el síntoma es una lista entera
  /// de caras grises sin ningún error a la vista. El tope es del endpoint, así que se respeta aquí y
  /// no en cada llamante (ver `photo_url_batches.dart`).
  @override
  Future<Map<String, String>> photoUrls(List<String> userIds) async {
    if (userIds.isEmpty) return const <String, String>{};

    // `toSet()`: la bandeja puede traer dos conversaciones con la misma persona en teoría, y
    // firmar dos veces la misma foto es trabajo y ancho de banda tirados. Y ahora además decide
    // cuántas tandas hacen falta, así que deduplicar antes de trocear no es cosmético.
    final List<String> ids = userIds.toSet().toList(growable: false);

    return fetchPhotoUrlsInBatches(ids, _photoUrlsBatch);
  }

  /// Una tanda: como mucho [photoUrlsBatchSize] ids.
  Future<Map<String, String>> _photoUrlsBatch(List<String> ids) async {
    final FunctionResponse response = await _client.functions.invoke(
      'profile-photo-view-url',
      body: <String, dynamic>{'user_ids': ids},
    );
    _throwIfError(response, 'No se pudo cargar la foto de perfil.');

    final Map<String, dynamic> data = _asMap(response.data);
    final Object? photos = data['photos'];
    if (photos is! Map) return const <String, String>{};

    // La función devuelve las claves TAL Y COMO SE PIDIERON, así que se busca por las mismas. Quien
    // no tenga foto sencillamente no sale del mapa: no se rellena con `null`, porque un `null`
    // guardado y un «todavía no lo he preguntado» se confunden en cuanto alguien cachea el mapa.
    final Map<String, String> result = <String, String>{};
    for (final String id in ids) {
      final Object? entry = photos[id];
      if (entry is! Map) continue;
      final Object? url = entry['url'];
      if (url is String && url.isNotEmpty) result[id] = url;
    }
    return result;
  }

  Map<String, dynamic> _asMap(Object? raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is String && raw.isNotEmpty) {
      final Object? decoded = jsonDecode(raw);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    }
    return const <String, dynamic>{};
  }

  /// Traduce el error del backend a algo que se le pueda enseñar a una persona.
  ///
  /// Los mensajes de `_shared/http.ts` están pensados para quien programa («El fichero subido no es
  /// una imagen», «photo_path no pertenece a este usuario»). Enseñar eso en una pantalla sería
  /// filtrar el diseño interno y no ayudaría a nadie a arreglar nada.
  void _throwIfError(FunctionResponse response, String fallback) {
    final int status = response.status;
    if (status >= 200 && status < 300) return;

    final Map<String, dynamic> data = _asMap(response.data);
    final String backendMessage = (data['message'] as String?) ?? '';

    // El único caso que el usuario puede corregir por su cuenta.
    if (backendMessage.contains('no es una imagen') ||
        backendMessage.contains('Los bytes son') ||
        backendMessage.contains('demasiado grande')) {
      throw const AvatarException(
        'Ese archivo no es una imagen válida. Prueba con otra foto.',
      );
    }

    throw AvatarException(fallback);
  }
}

/// Error del avatar ya traducido a lenguaje de persona, listo para enseñar en un `SnackBar`.
class AvatarException implements Exception {
  const AvatarException(this.message);

  final String message;

  @override
  String toString() => message;
}
