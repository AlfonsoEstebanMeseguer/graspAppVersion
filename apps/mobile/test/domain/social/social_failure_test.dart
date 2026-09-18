import 'package:flutter_test/flutter_test.dart';
import 'package:grasp_mobile/domain/social/message_input_state.dart';
import 'package:grasp_mobile/domain/social/social_failure.dart';

/// Tests de la traducción de errores del backend (`RN-21` y `RN-23`).
///
/// `RN-21` obliga a decir **cuál** es el límite alcanzado y **cuándo se recupera**, nunca a fallar
/// en silencio. `RN-23` obliga a que el bloqueo no se distinga de un cupo agotado. Las dos reglas
/// chocan y el ADR 0022 ya decidió quién gana; aquí se comprueba que el cliente respeta esa
/// decisión en vez de reintroducir la distinción al traducir.
Map<String, dynamic> _error(
  String code, {
  Map<String, dynamic>? details,
  String? message,
}) => <String, dynamic>{
  'error': code,
  'message': ?message,
  'details': ?details,
};

void main() {
  // Un instante fijo para que los tests no dependan del reloj de la máquina.
  final DateTime ahora = DateTime(2026, 8, 25, 14, 0);

  group('RN-21 — cada límite dice cuál es y cuándo se recupera', () {
    test('too_many_first_messages: el número Y la hora de recuperación', () {
      final SocialFailure failure = SocialFailure.fromResponse(
        422,
        _error(
          'send_blocked',
          details: <String, dynamic>{
            'reason': 'too_many_first_messages',
            'limit': 5,
            'retry_at': '2026-08-25T16:30:00+00:00',
          },
        ),
        now: ahora,
      );

      expect(failure.kind, SocialFailureKind.limitReached);
      expect(failure.limit, 5);
      expect(failure.message, contains('5'));
      expect(
        failure.message,
        contains('24 horas'),
        reason: 'RN-21 pide decir CUÁL es el límite alcanzado.',
      );
      expect(
        failure.message,
        contains(_horaLocal('2026-08-25T16:30:00+00:00')),
        reason: 'RN-21 pide decir CUÁNDO se recupera.',
      );
      // Sin esto, la comprobación de arriba solo detecta el `toLocal()` olvidado en una máquina
      // que NO esté en UTC — en una que sí lo esté (un CI, por ejemplo) sería vacua, porque la
      // hora local y la UTC coinciden. Esto lo caza en cualquier zona horaria.
      expect(
        failure.retryAt!.isUtc,
        isFalse,
        reason:
            'retryAt tiene que venir ya en hora local: la pantalla lo pinta tal cual y una hora '
            'UTC mostrada como local manda a la persona a reintentar a la hora equivocada.',
      );
    });

    test('too_many_pending_requests: el número, y NO inventa una hora', () {
      // Este cupo no lo libera el reloj, lo libera que alguien acepte. El backend manda
      // `retry_at: null` a propósito, y decir «a las 18:00» sería mentir — RN-21 pide decir la
      // VERDAD sobre cuándo se recupera.
      final SocialFailure failure = SocialFailure.fromResponse(
        422,
        _error(
          'send_blocked',
          details: <String, dynamic>{
            'reason': 'too_many_pending_requests',
            'limit': 5,
            'retry_at': null,
          },
        ),
        now: ahora,
      );

      expect(failure.kind, SocialFailureKind.limitReached);
      expect(failure.message, contains('5'));
      expect(failure.message, contains('acepte'));
      expect(failure.retryAt, isNull);
      expect(failure.message, isNot(matches(RegExp(r'\d{1,2}:\d{2}'))));
    });

    test('rate_limited de follow-toggle: 20 solicitudes en 24 h, con su hora', () {
      final SocialFailure failure = SocialFailure.fromResponse(
        422,
        _error(
          'rate_limited',
          details: <String, dynamic>{
            'limit': 20,
            'window_hours': 24,
            'retry_at': '2026-08-26T09:15:00+00:00',
          },
        ),
        now: ahora,
      );

      expect(failure.kind, SocialFailureKind.limitReached);
      expect(failure.message, contains('20'));
      expect(failure.message, contains('seguimiento'));
      expect(failure.message, contains(_horaLocal('2026-08-26T09:15:00+00:00')));
    });

    test('refresh_limit_reached de connect-feed', () {
      final SocialFailure failure = SocialFailure.fromResponse(
        422,
        _error(
          'refresh_limit_reached',
          details: <String, dynamic>{
            'limit': 10,
            'retry_at': '2026-08-26T00:00:00+00:00',
          },
        ),
        now: ahora,
      );

      expect(failure.kind, SocialFailureKind.limitReached);
      expect(failure.message, contains('10'));
      expect(failure.message.toLowerCase(), contains('actualiz'));
    });

    test('un límite sin `retry_at` nunca produce un mensaje mudo', () {
      final SocialFailure failure = SocialFailure.fromResponse(
        422,
        _error('rate_limited', details: <String, dynamic>{'limit': 20}),
        now: ahora,
      );
      expect(failure.message.trim(), isNotEmpty);
      expect(failure.message, contains('20'));
    });
  });

  group('RN-23 — el cupo agotado y el bloqueo dan EL MISMO texto', () {
    test('quota_exhausted usa la constante del ADR 0022, no un texto propio', () {
      // Un bloqueo llega exactamente así: `PublicSendBlockedReason` no tiene variante para el
      // bloqueo, así que los dos casos son este mismo cuerpo. Si aquí se compusiera un texto
      // «has gastado tus 5 mensajes», el bloqueado leería algo que no es verdad y —peor— cualquier
      // divergencia futura entre los dos textos delataría el bloqueo.
      final SocialFailure failure = SocialFailure.fromResponse(
        422,
        _error(
          'send_blocked',
          details: <String, dynamic>{
            'reason': 'quota_exhausted',
            'limit': 5,
            'retry_at': null,
          },
        ),
        now: ahora,
      );

      expect(failure.message, kMessageInputNotice);
    });

    test('ningún mensaje traducido menciona un bloqueo', () {
      for (final String code in <String>[
        'send_blocked',
        'not_found',
        'rate_limited',
        'forbidden',
      ]) {
        final SocialFailure failure = SocialFailure.fromResponse(
          code == 'not_found' ? 404 : 422,
          _error(code, details: <String, dynamic>{'reason': 'quota_exhausted'}),
          now: ahora,
        );
        expect(
          failure.message.toLowerCase(),
          isNot(contains('bloque')),
          reason: 'El texto de "$code" menciona un bloqueo (RN-23).',
        );
      }
    });

    test('un 404 de tag no distingue «no existe» de «hay bloqueo»', () {
      final SocialFailure failure = SocialFailure.fromResponse(
        404,
        _error('not_found'),
        now: ahora,
      );
      expect(failure.kind, SocialFailureKind.notFound);
      expect(failure.message.toLowerCase(), isNot(contains('bloque')));
    });
  });

  group('el mensaje interno del backend nunca llega a una pantalla', () {
    test('se conserva en rawCode para diagnóstico, no en message', () {
      // Hallazgo H-A-02 de la auditoría de 2026-08-15: el cliente no pinta mensajes internos.
      final SocialFailure failure = SocialFailure.fromResponse(
        500,
        _error(
          'internal_error',
          message: 'permission denied for table conversations',
        ),
        now: ahora,
      );

      expect(failure.kind, SocialFailureKind.unknown);
      expect(failure.message, isNot(contains('permission denied')));
      expect(failure.message, isNot(contains('conversations')));
      expect(failure.rawCode, contains('internal_error'));
    });

    test('un código desconocido tampoco se pinta tal cual', () {
      final SocialFailure failure = SocialFailure.fromResponse(
        418,
        _error('teapot_on_fire'),
        now: ahora,
      );
      expect(failure.message, isNot(contains('teapot_on_fire')));
      expect(failure.message.trim(), isNotEmpty);
    });
  });

  group('cada código HTTP del contrato cae en su clase', () {
    test('400 → invalidInput, 401 → unauthorized, 403 → forbidden, 409 → conflict', () {
      expect(
        SocialFailure.fromResponse(400, _error('invalid_input'), now: ahora).kind,
        SocialFailureKind.invalidInput,
      );
      expect(
        SocialFailure.fromResponse(401, _error('unauthorized'), now: ahora).kind,
        SocialFailureKind.unauthorized,
      );
      expect(
        SocialFailure.fromResponse(403, _error('forbidden'), now: ahora).kind,
        SocialFailureKind.forbidden,
      );
      expect(
        SocialFailure.fromResponse(409, _error('conflict'), now: ahora).kind,
        SocialFailureKind.conflict,
      );
    });

    test('422 own_tag se distingue de un límite', () {
      final SocialFailure failure = SocialFailure.fromResponse(
        422,
        _error('own_tag'),
        now: ahora,
      );
      expect(failure.kind, SocialFailureKind.ownTag);
      expect(failure.message.toLowerCase(), contains('tu propio tag'));
    });

    test('422 invalid_action no se confunde con un límite alcanzado', () {
      expect(
        SocialFailure.fromResponse(422, _error('invalid_action'), now: ahora).kind,
        SocialFailureKind.invalidAction,
      );
    });
  });

  group('formato de la hora de recuperación', () {
    test('hoy: solo la hora', () {
      final String texto = formatRetryAt(
        DateTime(2026, 8, 25, 14, 0),
        DateTime(2026, 8, 25, 16, 30),
      );
      expect(texto, 'a las 16:30');
    });

    test('mañana: lo dice, porque «a las 09:15» a secas se lee como hoy', () {
      final String texto = formatRetryAt(
        DateTime(2026, 8, 25, 14, 0),
        DateTime(2026, 8, 26, 9, 15),
      );
      expect(texto, 'mañana a las 09:15');
    });

    test('más adelante: con la fecha', () {
      final String texto = formatRetryAt(
        DateTime(2026, 8, 25, 14, 0),
        DateTime(2026, 8, 28, 9, 5),
      );
      expect(texto, 'el 28/08 a las 09:05');
    });

    test('los minutos van con dos dígitos', () {
      expect(
        formatRetryAt(DateTime(2026, 8, 25, 14, 0), DateTime(2026, 8, 25, 16, 5)),
        'a las 16:05',
      );
    });
  });
}

/// La hora local esperada para un instante UTC — el mismo cálculo que hace la implementación, para
/// que el test valga en cualquier zona horaria y no solo en la de esta máquina.
String _horaLocal(String iso) {
  final DateTime local = DateTime.parse(iso).toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}
