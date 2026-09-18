import 'package:grasp_mobile/domain/social/connect_candidate.dart';
import 'package:grasp_mobile/domain/social/connect_repository.dart';
import 'package:grasp_mobile/domain/social/follow_edge.dart';
import 'package:grasp_mobile/domain/social/social_failure.dart';
import 'package:grasp_mobile/domain/social/tag_lookup_result.dart';

/// Doble de [ConnectRepository] para los tests de la pantalla Conectar.
///
/// Guarda **qué se le pidió** además de qué devolvió: la mitad de las reglas del §6 no son sobre lo
/// que se pinta sino sobre **cuándo se llama al backend** (RN-45 la lista no se regenera al hacer
/// scroll, RN-46 el pull-to-refresh sí, RN-37 el filtro se reinicia). Sin registrar las llamadas,
/// esos tests no podrían distinguir nada.
class FakeConnectRepository implements ConnectRepository {
  FakeConnectRepository({List<ConnectFeedPage>? pages, this.tagResult})
    : _pages = pages ?? <ConnectFeedPage>[];

  final List<ConnectFeedPage> _pages;

  /// Lo que devuelve [lookupTag]. `null` = «no existe» **o** «hay bloqueo»: el backend no los
  /// distingue y este doble tampoco puede, que es justo lo que RN-23 garantiza.
  TagLookupResult? tagResult;

  /// Si no es `null`, [lookupTag] lanza esto (para `own_tag` y los fallos de red).
  Object? lookupFailure;

  /// Una entrada por llamada a [feed], en orden.
  final List<({Set<ConnectFilter> filters, bool refresh})> feedCalls =
      <({Set<ConnectFilter> filters, bool refresh})>[];

  final List<String> dismissed = <String>[];
  final List<String> tagsBuscados = <String>[];

  @override
  Future<ConnectFeedPage> feed({
    Set<ConnectFilter> filters = const <ConnectFilter>{},
    bool refresh = false,
  }) async {
    feedCalls.add((filters: Set<ConnectFilter>.of(filters), refresh: refresh));
    if (_pages.isEmpty) {
      return const ConnectFeedPage(
        candidates: <ConnectCandidate>[],
        emptyState: true,
        relaxed: false,
      );
    }
    // La última página se repite si se piden más llamadas que páginas hay: así un test que solo
    // define una tanda no revienta al hacer scroll.
    final int index = feedCalls.length - 1;
    return _pages[index < _pages.length ? index : _pages.length - 1];
  }

  @override
  Future<void> dismiss(String userId) async => dismissed.add(userId);

  @override
  Future<TagLookupResult?> lookupTag(String tag) async {
    tagsBuscados.add(tag);
    final Object? failure = lookupFailure;
    if (failure != null) throw failure;
    return tagResult;
  }
}

/// Constructor de candidatos con valores por defecto sensatos.
///
/// **No acepta ninguna categoría ni experiencia**, y no es una omisión: el ADR 0020 las deja fuera
/// del cliente entero, así que ni siquiera se puede escribir un test que las mande.
ConnectCandidate fakeCandidate({
  required String userId,
  String displayName = 'Alguien',
  String tag = 'alguien#K7M2QX9F',
  int? age = 29,
  String? bio = 'Una bio cualquiera.',
  bool hasPhoto = false,
  bool isActive = false,
  String? listenerProfile,
  int timeHelpingSeconds = 0,
  int streakDays = 0,
}) => ConnectCandidate(
  userId: userId,
  displayName: displayName,
  tag: tag,
  age: age,
  bio: bio,
  hasPhoto: hasPhoto,
  isActive: isActive,
  listenerProfile: listenerProfile,
  timeHelpingSeconds: timeHelpingSeconds,
  streakDays: streakDays,
);

/// Una tanda del feed.
ConnectFeedPage fakePage(
  List<ConnectCandidate> candidates, {
  bool relaxed = false,
}) => ConnectFeedPage(
  candidates: candidates,
  emptyState: candidates.isEmpty,
  relaxed: relaxed,
);

/// Un resultado de búsqueda por tag.
TagLookupResult fakeTagResult({
  String userId = '00000000-0000-4000-8000-0000000000ff',
  String displayName = 'Encontrada',
  String tag = 'encontrada#K7M2QX9F',
  String? bio = 'Hola.',
  FollowState followState = FollowState.none,
}) => TagLookupResult(
  userId: userId,
  displayName: displayName,
  tag: tag,
  bio: bio,
  hasPhoto: false,
  followState: followState,
  timeHelpingSeconds: 0,
  streakDays: 0,
);

/// Un `SocialFailure` de tag propio, que es el único desenlace del §6.2 que **sí** se distingue.
const SocialFailure ownTagFailure = SocialFailure(
  SocialFailureKind.ownTag,
  'Ese es tu propio tag.',
);
