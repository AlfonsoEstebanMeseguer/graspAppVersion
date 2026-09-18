import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'social_error_mapper.dart';

/// Llama a una Edge Function de la capa social y devuelve su cuerpo, **traduciendo cualquier
/// error** a un `SocialFailure` con el texto ya en castellano.
///
/// Un solo sitio para el `try`/`catch`, y es deliberado: hay trece funciones que llamar y
/// repetirlo en cada una garantiza que alguna se quede sin él. Justo esa es la forma del fallo que
/// arrastra `SupabaseAvatarRepository`, que comprueba `response.status` **después** de un `invoke`
/// que ya lanzó (ver [mapSocialError]).
Future<Map<String, dynamic>> invokeEdge(
  SupabaseClient client,
  String name, {
  Map<String, dynamic>? body,
  Map<String, dynamic>? query,
  HttpMethod method = HttpMethod.post,
}) async {
  try {
    final FunctionResponse response = await client.functions.invoke(
      name,
      body: body,
      queryParameters: query,
      method: method,
    );
    return _asMap(response.data);
  } on Object catch (error) {
    throw mapSocialError(error);
  }
}

Map<String, dynamic> _asMap(Object? raw) {
  if (raw is Map<String, dynamic>) return raw;
  if (raw is Map) return Map<String, dynamic>.from(raw);
  if (raw is String && raw.isNotEmpty) {
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } on FormatException {
      // Un 200 cuyo cuerpo no es JSON. Cae a vacío y el llamante lo trata como respuesta sin datos.
    }
  }
  return const <String, dynamic>{};
}
