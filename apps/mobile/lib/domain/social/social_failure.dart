import 'message_input_state.dart';

/// Por qué falló una operación social (mensajería, seguimientos, Conectar, moderación).
///
/// Expone la **causa**, no un código del backend: los literales de `_shared/http.ts` están escritos
/// para quien programa y enseñarlos filtraría el diseño interno sin ayudar a nadie (hallazgo H-A-02
/// de la auditoría de 2026-08-15).
enum SocialFailureKind {
  /// `400 invalid_input`. En la práctica solo llega por una carrera: la pantalla valida antes.
  invalidInput,

  /// `401 unauthorized`: el JWT no vale o falta.
  unauthorized,

  /// `403 forbidden`: aceptar o ignorar una solicitud que enviaste tú, o editar/borrar para todos
  /// un mensaje que no escribiste.
  forbidden,

  /// `404 not_found`.
  ///
  /// **Deliberadamente ambiguo, y no se puede desambiguar**: el backend devuelve el mismo cuerpo
  /// para «no existe», «no participas» y «hay un bloqueo». Un 403 en el segundo caso confirmaría
  /// que esa conversación existe, y distinguir el tercero delataría el bloqueo (`RN-23`).
  notFound,

  /// `409 conflict`: el mensaje cambió mientras se aplicaba la acción. Quien pierde la carrera lo
  /// sabe, en vez de que su borrado se descarte en silencio.
  conflict,

  /// `422 invalid_action` / `invalid_reply_target`: la acción no cabe en ese estado.
  invalidAction,

  /// `422 own_tag`: buscaste tu propio tag.
  ownTag,

  /// Un tope alcanzado (`RN-18`, `RN-19`, `RN-20`, `RN-01`, `RN-46`). [SocialFailure.message] dice
  /// **cuál** y **cuándo se recupera** — eso es `RN-21`.
  limitReached,

  /// Fallo de red o servidor inalcanzable.
  network,

  /// `500 internal_error` o cualquier otra cosa.
  unknown,
}

/// Un fallo del backend ya traducido a algo que se le puede enseñar a una persona.
///
/// Mismo patrón que `AccountDeletionFailure` y `AuthFailure`: la causa en [kind], el texto en
/// [message], y el código original en [rawCode] **solo para diagnóstico**.
class SocialFailure implements Exception {
  const SocialFailure(
    this.kind,
    this.message, {
    this.rawCode,
    this.limit,
    this.retryAt,
  });

  /// Traduce una respuesta de Edge Function.
  ///
  /// [now] entra por parámetro para que los tests no dependan del reloj de la máquina — el mismo
  /// patrón que `evaluateSendLimits` en el backend.
  factory SocialFailure.fromResponse(
    int status,
    Map<String, dynamic> body, {
    DateTime? now,
  }) {
    final DateTime ahora = now ?? DateTime.now();
    final String code = (body['error'] as String?) ?? '';
    final Map<String, dynamic> details = _asMap(body['details']);

    final int? limit = (details['limit'] as num?)?.toInt();
    final Object? rawRetry = details['retry_at'];
    final DateTime? retryAt = rawRetry is String
        ? DateTime.tryParse(rawRetry)?.toLocal()
        : null;

    SocialFailure limite(String texto) => SocialFailure(
      SocialFailureKind.limitReached,
      texto,
      rawCode: code,
      limit: limit,
      retryAt: retryAt,
    );

    switch (status) {
      case 400:
        return SocialFailure(
          SocialFailureKind.invalidInput,
          'No se pudo completar la acción. Revisa los datos e inténtalo de nuevo.',
          rawCode: code,
        );
      case 401:
        return SocialFailure(
          SocialFailureKind.unauthorized,
          'Tu sesión ha caducado. Vuelve a iniciar sesión.',
          rawCode: code,
        );
      case 403:
        return SocialFailure(
          SocialFailureKind.forbidden,
          'No puedes hacer eso en esta conversación.',
          rawCode: code,
        );
      case 404:
        // Un solo texto para los tres casos que el backend no distingue. Ver [notFound].
        return SocialFailure(
          SocialFailureKind.notFound,
          'No se ha encontrado.',
          rawCode: code,
        );
      case 409:
        return SocialFailure(
          SocialFailureKind.conflict,
          'Ese mensaje cambió mientras lo hacías. Vuelve a intentarlo.',
          rawCode: code,
        );
      case 422:
        switch (code) {
          case 'send_blocked':
            return limite(_sendBlockedMessage(details, limit, retryAt, ahora));
          case 'rate_limited':
            return limite(
              'Has enviado ${limit ?? 20} solicitudes de seguimiento en las últimas '
              '${(details['window_hours'] as num?)?.toInt() ?? 24} horas. '
              '${_podrasEnviarMas(retryAt, ahora)}',
            );
          case 'refresh_limit_reached':
            return limite(
              'Has actualizado la lista ${limit ?? 0} veces hoy. '
              '${_podrasVolver(retryAt, ahora)}',
            );
          case 'own_tag':
            return SocialFailure(
              SocialFailureKind.ownTag,
              'Ese es tu propio tag.',
              rawCode: code,
            );
          default:
            return SocialFailure(
              SocialFailureKind.invalidAction,
              'Esa acción ya no es posible en esta conversación.',
              rawCode: code,
            );
        }
      default:
        return SocialFailure(
          SocialFailureKind.unknown,
          'Algo ha fallado. Inténtalo de nuevo en un momento.',
          rawCode: code.isEmpty ? 'http_$status' : code,
        );
    }
  }

  /// Fallo de red, sin respuesta del servidor.
  factory SocialFailure.network([Object? cause]) => SocialFailure(
    SocialFailureKind.network,
    'No hay conexión. Comprueba tu red e inténtalo de nuevo.',
    rawCode: cause?.toString(),
  );

  final SocialFailureKind kind;

  /// El texto en castellano, listo para un `SnackBar`. **Nunca contiene el mensaje interno del
  /// backend** ni la palabra «bloqueo».
  final String message;

  /// El código original. Para logs y diagnóstico — **nunca se pinta**.
  final String? rawCode;

  /// El número del límite alcanzado (`RN-21`), si lo hay.
  final int? limit;

  /// Cuándo se recupera el cupo, en hora **local**. `null` cuando no depende del reloj.
  final DateTime? retryAt;

  @override
  String toString() => 'SocialFailure(${kind.name}, raw: $rawCode)';
}

/// El texto de un `422 send_blocked`, que es donde `RN-21` y `RN-23` chocan.
///
/// **`quota_exhausted` devuelve [kMessageInputNotice] y nada más.** Un bloqueo llega exactamente
/// con este mismo cuerpo —`PublicSendBlockedReason` no tiene variante para el bloqueo—, así que
/// componer aquí un «has gastado tus 5 mensajes» le diría al bloqueado algo que no es verdad y, lo
/// que importa, **cualquier divergencia futura entre los dos textos delataría el bloqueo**. Lo
/// decide el ADR 0022.
String _sendBlockedMessage(
  Map<String, dynamic> details,
  int? limit,
  DateTime? retryAt,
  DateTime now,
) {
  switch (details['reason'] as String?) {
    case 'too_many_pending_requests':
      // Sin hora A PROPÓSITO: este cupo no lo libera el reloj, lo libera que alguien acepte.
      // Inventar un instante sería mentir, y `RN-21` pide decir la verdad sobre cuándo se recupera.
      return 'Tienes ${limit ?? 5} solicitudes de mensaje esperando respuesta. '
          'Podrás enviar más cuando alguien acepte alguna.';
    case 'too_many_first_messages':
      return 'Has iniciado ${limit ?? 5} conversaciones nuevas en las últimas 24 horas. '
          '${_podrasIniciarOtra(retryAt, now)}';
    default:
      // `quota_exhausted` y cualquier cosa que no se reconozca. Ver el bloque de arriba.
      return kMessageInputNotice;
  }
}

String _podrasEnviarMas(DateTime? retryAt, DateTime now) => retryAt == null
    ? 'Inténtalo de nuevo más tarde.'
    : 'Podrás enviar más ${formatRetryAt(now, retryAt)}.';

String _podrasIniciarOtra(DateTime? retryAt, DateTime now) => retryAt == null
    ? 'Inténtalo de nuevo más tarde.'
    : 'Podrás iniciar otra ${formatRetryAt(now, retryAt)}.';

String _podrasVolver(DateTime? retryAt, DateTime now) => retryAt == null
    ? 'Inténtalo de nuevo más tarde.'
    : 'Podrás volver a actualizarla ${formatRetryAt(now, retryAt)}.';

/// «cuándo se recupera», en palabras (`RN-21`).
///
/// Los dos instantes van en hora **local**. Se distingue hoy / mañana / más adelante porque
/// «a las 09:15» a secas se lee como hoy, y un cupo que vuelve mañana leído como hoy hace que la
/// persona reintente en balde y crea que la app está rota.
String formatRetryAt(DateTime now, DateTime retryAt) {
  final String hora =
      '${retryAt.hour.toString().padLeft(2, '0')}:'
      '${retryAt.minute.toString().padLeft(2, '0')}';

  final DateTime hoy = DateTime(now.year, now.month, now.day);
  final DateTime dia = DateTime(retryAt.year, retryAt.month, retryAt.day);
  final int diferencia = dia.difference(hoy).inDays;

  if (diferencia <= 0) return 'a las $hora';
  if (diferencia == 1) return 'mañana a las $hora';

  final String fecha =
      '${retryAt.day.toString().padLeft(2, '0')}/'
      '${retryAt.month.toString().padLeft(2, '0')}';
  return 'el $fecha a las $hora';
}

Map<String, dynamic> _asMap(Object? raw) {
  if (raw is Map<String, dynamic>) return raw;
  if (raw is Map) return Map<String, dynamic>.from(raw);
  return const <String, dynamic>{};
}
