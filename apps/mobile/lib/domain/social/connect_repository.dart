import 'connect_candidate.dart';
import 'tag_lookup_result.dart';

/// Contrato de la pantalla Conectar (§6).
abstract interface class ConnectRepository {
  /// Una tanda del feed (`connect-feed`).
  ///
  /// [filters] vacío es `Todos` (`RN-35`). [refresh] a `true` es el `pull-to-refresh`, y **cuenta
  /// para el tope de `RN-46`**: el contador se incrementa **antes** de decidir, así que un intento
  /// rechazado también lo sube. Es correcto — la fecha va en la clave y se reinicia solo a las
  /// 00:00 UTC.
  ///
  /// Lanza `SocialFailure` con [SocialFailureKind.limitReached] al agotar los refrescos, con el
  /// límite y la hora ya en el texto (`RN-21`).
  Future<ConnectFeedPage> feed({
    Set<ConnectFilter> filters = const <ConnectFilter>{},
    bool refresh = false,
  });

  /// «No mostrar más» sobre alguien del feed (`connect-dismiss`, §6.4 decisión 8).
  ///
  /// `RN-48`: **los rechazos no caducan nunca**, y no hay forma de deshacerlos desde la app — no
  /// existe pantalla que liste a quién has ocultado, y por eso `connect_dismissals` tampoco concede
  /// `select`. El `✕` de la tarjeta es la única puerta, así que conviene que no sea fácil de rozar.
  ///
  /// Idempotente por forma: descartar dos veces a la misma persona es un no-op.
  Future<void> dismiss(String userId);

  /// Busca un tag **exacto** (`connect-tag-lookup`, §6.2). Sin búsqueda difusa.
  ///
  /// ## Los dos desenlaces que el cliente NO puede distinguir
  ///
  /// «No existe» y «hay un bloqueo en alguna dirección» devuelven **el mismo 404, mismo cuerpo**
  /// (`RN-23`). Devuelve `null` en los dos casos, y **eso es la garantía escrita en la firma**: no
  /// hay tipo de retorno que permita a la pantalla ramificar por ese motivo.
  ///
  /// La pantalla pinta «No existe ningún usuario con ese tag» con el **mismo widget** en ambos —
  /// sin rama propia, porque una rama distinta acaba divergiendo en un detalle visible.
  ///
  /// Buscar el tag propio sí es distinto: lanza `SocialFailure` con [SocialFailureKind.ownTag].
  Future<TagLookupResult?> lookupTag(String tag);
}
