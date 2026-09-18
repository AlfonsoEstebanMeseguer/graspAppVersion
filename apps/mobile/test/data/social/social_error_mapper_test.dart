import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:grasp_mobile/data/social/social_error_mapper.dart';
import 'package:grasp_mobile/domain/social/message_input_state.dart';
import 'package:grasp_mobile/domain/social/social_failure.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Tests del traductor de errores de la capa social.
///
/// ## El detalle que hace falta este fichero
///
/// En `functions_client 2.6.4`, `functions.invoke` **lanza `FunctionException`** en cuanto la
/// respuesta no es 2xx: nunca devuelve un `FunctionResponse` con un status de error. Un repositorio
/// escrito como
///
/// ```dart
/// final FunctionResponse r = await client.functions.invoke(...);
/// if (r.status >= 400) throw MiError();   // <- INALCANZABLE
/// ```
///
/// no traduce nada: la excepción cruda sube hasta la pantalla y la persona ve
/// `FunctionException(status: 422, details: {...})`. Por eso aquí se traduce **desde la excepción**
/// y hay tests que lo fijan.
void main() {
  final DateTime ahora = DateTime(2026, 8, 25, 14, 0);

  group('FunctionException — el camino real de un error de Edge Function', () {
    test('un 422 con límite se traduce con su número y su hora (RN-21)', () {
      final SocialFailure failure = mapSocialError(
        const FunctionException(
          status: 422,
          details: <String, dynamic>{
            'error': 'send_blocked',
            'details': <String, dynamic>{
              'reason': 'too_many_first_messages',
              'limit': 5,
              'retry_at': '2026-08-25T16:30:00+00:00',
            },
          },
        ),
        now: ahora,
      );

      expect(failure.kind, SocialFailureKind.limitReached);
      expect(failure.limit, 5);
      expect(failure.message, contains('5'));
      // La hora se calcula, no se incrusta: el `retry_at` viaja en UTC y se pinta en hora local,
      // así que un literal «16:30» solo valdría en una máquina en UTC. (La primera versión de
      // este test lo tenía incrustado y falló en esta máquina, que va en UTC+2.)
      final DateTime local = DateTime.parse(
        '2026-08-25T16:30:00+00:00',
      ).toLocal();
      expect(
        failure.message,
        contains(
          '${local.hour.toString().padLeft(2, '0')}:'
          '${local.minute.toString().padLeft(2, '0')}',
        ),
      );
      expect(failure.retryAt!.isUtc, isFalse);
    });

    test('un bloqueo llega como quota_exhausted y da el texto único (RN-23)', () {
      final SocialFailure failure = mapSocialError(
        const FunctionException(
          status: 422,
          details: <String, dynamic>{
            'error': 'send_blocked',
            'details': <String, dynamic>{
              'reason': 'quota_exhausted',
              'limit': 5,
              'retry_at': null,
            },
          },
        ),
        now: ahora,
      );
      expect(failure.message, kMessageInputNotice);
    });

    test('un 404 no dice si es «no existe», «no participas» o un bloqueo', () {
      final SocialFailure failure = mapSocialError(
        const FunctionException(
          status: 404,
          details: <String, dynamic>{'error': 'not_found'},
        ),
        now: ahora,
      );
      expect(failure.kind, SocialFailureKind.notFound);
      expect(failure.message.toLowerCase(), isNot(contains('bloque')));
    });

    test('unos `details` que no son JSON no revientan el traductor', () {
      // `functions_client` mete el texto crudo en `details` cuando el cuerpo dice ser JSON y no
      // parsea — pasa con un 502 de un proxy, que devuelve HTML. Reventar aquí convertiría un
      // error del servidor en un crash de la app.
      final SocialFailure failure = mapSocialError(
        const FunctionException(
          status: 502,
          details: '<html><body>Bad Gateway</body></html>',
        ),
        now: ahora,
      );
      expect(failure.kind, SocialFailureKind.unknown);
      expect(failure.message, isNot(contains('html')));
      expect(failure.message.trim(), isNotEmpty);
    });

    test('unos `details` en forma de cadena JSON se parsean igual', () {
      final SocialFailure failure = mapSocialError(
        const FunctionException(
          status: 404,
          details: '{"error":"not_found"}',
        ),
        now: ahora,
      );
      expect(failure.kind, SocialFailureKind.notFound);
    });

    test('`details` nulos caen en unknown sin lanzar', () {
      expect(
        mapSocialError(
          const FunctionException(status: 500),
          now: ahora,
        ).kind,
        SocialFailureKind.unknown,
      );
    });
  });

  group('PostgrestException — las lecturas directas de user_follows', () {
    test('un 401/403 de PostgREST se traduce, no se pinta crudo', () {
      final SocialFailure failure = mapSocialError(
        const PostgrestException(
          message: 'permission denied for table user_follows',
          code: '42501',
        ),
        now: ahora,
      );
      expect(failure.message, isNot(contains('permission denied')));
      expect(failure.message, isNot(contains('user_follows')));
      expect(failure.rawCode, isNotNull);
    });

    test('el tope de activity_status (más de 500 ids) no se pinta crudo', () {
      final SocialFailure failure = mapSocialError(
        const PostgrestException(
          message: 'activity_status admite como maximo 500 ids por llamada',
          code: '54000',
        ),
        now: ahora,
      );
      expect(failure.message, isNot(contains('activity_status')));
      expect(failure.message.trim(), isNotEmpty);
    });
  });

  group('fallos de red', () {
    test('un SocketException es un fallo de red, no un error desconocido', () {
      final SocialFailure failure = mapSocialError(
        const SocketException('no route to host'),
        now: ahora,
      );
      expect(failure.kind, SocialFailureKind.network);
      expect(failure.message.toLowerCase(), contains('conexión'));
    });

    test('un TimeoutException también', () {
      expect(
        mapSocialError(TimeoutException('tardó demasiado'), now: ahora).kind,
        SocialFailureKind.network,
      );
    });
  });

  group('un SocialFailure ya traducido no se vuelve a envolver', () {
    test('pasa tal cual, conservando su texto', () {
      const SocialFailure original = SocialFailure(
        SocialFailureKind.ownTag,
        'Ese es tu propio tag.',
      );
      expect(identical(mapSocialError(original, now: ahora), original), isTrue);
    });
  });

  group('cualquier otra cosa', () {
    test('no llega cruda a la pantalla', () {
      final SocialFailure failure = mapSocialError(
        StateError('null check operator on a null value'),
        now: ahora,
      );
      expect(failure.kind, SocialFailureKind.unknown);
      expect(failure.message, isNot(contains('null check')));
      expect(failure.rawCode, contains('null check'));
    });
  });
}
