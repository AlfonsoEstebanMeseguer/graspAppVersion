import 'package:flutter/foundation.dart';

import 'follow_edge.dart';

/// Una fila de la lista de **Usuarios bloqueados** (Perfil → Privacidad).
///
/// ## Por qué lleva la fecha
///
/// No es decoración: una lista de bloqueados sin fecha no se puede usar para decidir. Quien entra
/// aquí meses después necesita saber cuál es cuál, y el nombre no siempre basta — el mismo motivo
/// por el que `RN-52` obliga a pintar el tag en cada fila.
@immutable
class BlockedUser {
  const BlockedUser({required this.profile, required this.blockedAt});

  /// Construye desde una fila de `blocks` con el perfil **incrustado** bajo la clave `blocked`.
  factory BlockedUser.fromJson(Map<String, dynamic> row) => BlockedUser(
    profile: SocialProfileRef.fromJson(
      Map<String, dynamic>.from(row['blocked'] as Map),
    ),
    blockedAt: DateTime.parse(row['created_at'] as String).toLocal(),
  );

  final SocialProfileRef profile;

  /// Cuándo se bloqueó. Ya en local: `created_at` viaja en UTC.
  final DateTime blockedAt;
}
