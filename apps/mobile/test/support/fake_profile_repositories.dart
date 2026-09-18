import 'package:grasp_mobile/domain/profile/profile.dart';
import 'package:grasp_mobile/domain/profile/profile_badge.dart';
import 'package:grasp_mobile/domain/profile/profile_repository.dart';
import 'package:grasp_mobile/domain/social/activity_repository.dart';

/// Doble de [ProfileRepository] para los tests de la Tarea 24.
///
/// Implementa el **contrato del dominio**, no el cliente de Supabase (punto 6 de la skill
/// `flutter-ui`). Lo que finge es lo que la base ya devuelve; las reglas que la base impone —el
/// `check` de 160 de `bio`, el tope de 24 h del tag— se prueban en su sitio, no aquí.
class FakeProfileRepository implements ProfileRepository {
  FakeProfileRepository({Profile? profile})
    : profile = profile ?? fakeProfile();

  Profile profile;

  int fetchCalls = 0;

  /// Si no es `null`, [fetchOwn] lanza esto.
  Object? fetchFailsWith;

  /// Lo escrito por [updateBio]. Se guarda la lista entera y no el último valor: así un test puede
  /// afirmar que **no** se llamó, que es distinto de que se llamara con `null`.
  final List<String?> bios = <String?>[];

  /// Si no es `null`, [updateBio] lanza esto.
  Object? bioFailsWith;

  final List<bool> hideActivityWrites = <bool>[];
  Object? hideActivityFailsWith;

  /// Lo que devuelve [rotateTag]. Cada llamada consume uno; al agotarse repite el último.
  List<String> tagsARotar = <String>['nuevo#TAG12345'];
  int rotateCalls = 0;

  /// Si no es `null`, [rotateTag] lanza esto — el 422 del tope de 24 h, por ejemplo.
  Object? rotateFailsWith;

  DateTime? nextRotationAt;

  final List<
    ({String? displayName, DateTime? birthDate, String? gender, String? country})
  >
  updates =
      <({String? displayName, DateTime? birthDate, String? gender, String? country})>[];

  @override
  Future<Profile> fetchOwn() async {
    fetchCalls++;
    final Object? error = fetchFailsWith;
    if (error != null) throw error;
    return profile;
  }

  @override
  Future<void> updateProfile({
    String? displayName,
    DateTime? birthDate,
    String? gender,
    String? country,
  }) async {
    updates.add((
      displayName: displayName,
      birthDate: birthDate,
      gender: gender,
      country: country,
    ));
  }

  @override
  Future<void> updateBio(String? bio) async {
    bios.add(bio);
    final Object? error = bioFailsWith;
    if (error != null) throw error;
    profile = bio == null
        ? profile.copyWith(limpiarBio: true)
        : profile.copyWith(bio: bio);
  }

  @override
  Future<void> setHideActivityStatus(bool hidden) async {
    hideActivityWrites.add(hidden);
    final Object? error = hideActivityFailsWith;
    if (error != null) throw error;
    profile = profile.copyWith(hideActivityStatus: hidden);
  }

  @override
  Future<TagRotation> rotateTag() async {
    rotateCalls++;
    final Object? error = rotateFailsWith;
    if (error != null) throw error;

    final String nuevo = tagsARotar[
        rotateCalls - 1 < tagsARotar.length ? rotateCalls - 1 : tagsARotar.length - 1];
    profile = profile.copyWith(tag: nuevo);
    return TagRotation(tag: nuevo, nextRotationAt: nextRotationAt);
  }
}

/// Un [Profile] con valores por defecto sensatos.
///
/// Lo que un test **no** menciona es lo que no le importa; lo que menciona es exactamente lo que
/// está comprobando.
Profile fakeProfile({
  String userId = '00000000-0000-4000-8000-000000000001',
  String? displayName = 'Alfonso',
  String? tag = 'alfon#K7M2QX9F',
  String? bio,
  bool hideActivityStatus = false,
  int followersCount = 0,
  int followingCount = 0,
  List<ProfileBadge> badges = const <ProfileBadge>[],
}) => Profile(
  userId: userId,
  displayName: displayName,
  tag: tag,
  bio: bio,
  hideActivityStatus: hideActivityStatus,
  followersCount: followersCount,
  followingCount: followingCount,
  badges: badges,
);

/// Doble de [ActivityRepository]: cuenta los latidos (`RN-30`, paso 4 de la Tarea 24).
class FakeActivityRepository implements ActivityRepository {
  int heartbeats = 0;

  /// Si no es `null`, [heartbeat] lanza esto. Un latido que falla **no puede tirar la app**.
  Object? failWith;

  Map<String, bool> statuses = const <String, bool>{};
  final List<List<String>> statusCalls = <List<String>>[];

  @override
  Future<void> heartbeat() async {
    heartbeats++;
    final Object? error = failWith;
    if (error != null) throw error;
  }

  @override
  Future<Map<String, bool>> activeStatus(List<String> userIds) async {
    statusCalls.add(List<String>.unmodifiable(userIds));
    return statuses;
  }
}
