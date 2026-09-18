import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/social/social_failure.dart';

/// Traduce **cualquier** cosa que pueda salir mal en la capa social a un [SocialFailure] con el
/// texto ya en castellano.
///
/// ## Por qué se traduce desde la EXCEPCIÓN y no desde el status de la respuesta
///
/// En `functions_client 2.6.4`, `functions.invoke` **lanza `FunctionException`** en cuanto la
/// respuesta no es 2xx — nunca devuelve un `FunctionResponse` con status de error. El patrón
///
/// ```dart
/// final FunctionResponse r = await client.functions.invoke(...);
/// if (r.status >= 400) throw MiError();   // INALCANZABLE
/// ```
///
/// deja el error sin traducir y la excepción cruda sube hasta la pantalla. Por eso todas las
/// llamadas de esta capa van envueltas en `try`/`catch` y pasan por aquí.
///
/// [now] entra por parámetro para que los tests no dependan del reloj de la máquina.
SocialFailure mapSocialError(Object error, {DateTime? now}) {
  // Ya traducido: no se vuelve a envolver, o el texto bueno se perdería detrás de uno genérico.
  if (error is SocialFailure) return error;

  if (error is FunctionException) {
    return SocialFailure.fromResponse(
      error.status,
      _bodyOf(error.details),
      now: now,
    );
  }

  if (error is AuthException) {
    return SocialFailure(
      SocialFailureKind.unauthorized,
      'Tu sesión ha caducado. Vuelve a iniciar sesión.',
      rawCode: error.message,
    );
  }

  if (error is PostgrestException) {
    // El mensaje de Postgres nombra tablas, columnas y policies. Enseñarlo filtraría el diseño
    // interno y no ayudaría a nadie a arreglar nada (hallazgo H-A-02 de la auditoría de
    // 2026-08-15), así que se conserva **solo** en `rawCode`.
    return SocialFailure(
      _postgrestKind(error.code),
      _postgrestMessage(error.code),
      rawCode: '${error.code}: ${error.message}',
    );
  }

  if (error is SocketException ||
      error is TimeoutException ||
      error is http.ClientException ||
      error is HandshakeException) {
    return SocialFailure.network(error);
  }

  return SocialFailure(
    SocialFailureKind.unknown,
    'Algo ha fallado. Inténtalo de nuevo en un momento.',
    rawCode: error.toString(),
  );
}

SocialFailureKind _postgrestKind(String? code) => switch (code) {
  '42501' => SocialFailureKind.forbidden, // insufficient_privilege
  'PGRST301' => SocialFailureKind.unauthorized, // JWT inválido o caducado
  'PGRST116' => SocialFailureKind.notFound, // 0 filas donde se esperaba 1
  _ => SocialFailureKind.unknown,
};

String _postgrestMessage(String? code) => switch (code) {
  '42501' => 'No tienes permiso para ver eso.',
  'PGRST301' => 'Tu sesión ha caducado. Vuelve a iniciar sesión.',
  'PGRST116' => 'No se ha encontrado.',
  _ => 'Algo ha fallado. Inténtalo de nuevo en un momento.',
};

/// El cuerpo de un `FunctionException`, venga como venga.
///
/// `functions_client` mete en `details` lo que pudo: un `Map` si el cuerpo era JSON válido, y el
/// **texto crudo** si decía ser JSON y no parseaba (un 502 de un proxy que devuelve HTML, por
/// ejemplo). Reventar aquí convertiría un error del servidor en un crash de la app, así que
/// cualquier cosa que no se entienda cae a un mapa vacío y acaba en `unknown`.
Map<String, dynamic> _bodyOf(Object? details) {
  if (details is Map<String, dynamic>) return details;
  if (details is Map) return Map<String, dynamic>.from(details);
  if (details is String && details.isNotEmpty) {
    try {
      final Object? decoded = jsonDecode(details);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } on FormatException {
      // No era JSON. Cae abajo.
    }
  }
  return const <String, dynamic>{};
}
