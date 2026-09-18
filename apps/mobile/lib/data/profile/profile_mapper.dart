import '../../domain/profile/avatar_type.dart';
import '../../domain/profile/profile.dart';
import '../../domain/profile/profile_badge.dart';

/// Columnas de `profiles` que necesita [mapProfileRows].
///
/// Vive aquí y no incrustada en el repositorio para que el `select` y el mapeo
/// no puedan divergir sin que se note: si alguien lee una columna que no está
/// en esta lista, PostgREST no la devuelve y el campo llega `null` en
/// silencio.
const String profilePublicColumns =
    'display_name, photo_path, preset_avatar, level, xp, '
    'streak_days, rooms_joined_count, time_helping_seconds, followers_count, '
    'following_count, tag, bio';

/// Construye el [Profile] a partir de las filas crudas que devuelve Supabase.
///
/// Función pura a propósito: sin `SupabaseClient`, sin red y sin sesión, para
/// que el mapeo sea testeable. El I/O se queda en
/// `SupabaseProfileRepository`.
///
/// [privateRow] y [onboardingRow] son opcionales porque pueden no existir: un
/// usuario recién dado de alta puede no tener fila en `profiles_private` (si el
/// trigger aún no corrió) ni en `onboarding_responses` (si no completó el
/// cuestionario).
///
/// [now] existe únicamente para que la edad sea determinista en los tests. En
/// producción nadie lo pasa.
Profile mapProfileRows({
  required String userId,
  required Map<String, dynamic> publicRow,
  Map<String, dynamic>? privateRow,
  Map<String, dynamic>? onboardingRow,
  List<ProfileBadge> badges = const <ProfileBadge>[],
  DateTime? now,
}) {
  final Map<String, dynamic> responses =
      (onboardingRow?['responses'] as Map<String, dynamic>?) ??
      const <String, dynamic>{};

  final String? birthDateIso = privateRow?['birth_date'] as String?;
  final DateTime? birthDate =
      birthDateIso == null ? null : DateTime.tryParse(birthDateIso);

  return Profile(
    userId: userId,
    displayName: publicRow['display_name'] as String?,
    photoPath: publicRow['photo_path'] as String?,
    presetAvatar: AvatarType.fromSlug(publicRow['preset_avatar'] as String?),
    level: (publicRow['level'] as int?) ?? 1,
    xp: (publicRow['xp'] as int?) ?? 0,
    streakDays: (publicRow['streak_days'] as int?) ?? 0,
    roomsJoinedCount: (publicRow['rooms_joined_count'] as int?) ?? 0,
    timeHelpingSeconds: (publicRow['time_helping_seconds'] as int?) ?? 0,
    followersCount: (publicRow['followers_count'] as int?) ?? 0,
    followingCount: (publicRow['following_count'] as int?) ?? 0,
    age: _ageFrom(birthDate, now ?? DateTime.now()),
    birthDate: birthDate,
    gender: privateRow?['gender'] as String?,
    country: privateRow?['country'] as String?,
    tag: publicRow['tag'] as String?,
    bio: publicRow['bio'] as String?,
    // Ausente = `false`, que es el default de la columna. Fallar hacia «no oculto» es lo correcto
    // aquí y solo aquí: este mapeo construye el perfil PROPIO, así que el peor caso es que su dueño
    // vea el interruptor apagado cuando debería estar encendido — molesto y visible. Quien decide si
    // el punto se pinta a TERCEROS es el RPC `activity_status`, que lee la columna de verdad.
    hideActivityStatus: privateRow?['hide_activity_status'] == true,
    badges: badges,
    interests: _stringList(responses['interests']),
    privateAnswers: <String, String>{
      if (responses['situation'] is String)
        'situation': responses['situation'] as String,
      if (responses['profile'] is String)
        'profile': responses['profile'] as String,
      if (responses['discovery'] is String)
        'discovery': responses['discovery'] as String,
    },
  );
}

List<String> _stringList(Object? raw) {
  if (raw is! List) return const <String>[];
  return <String>[for (final Object? item in raw) if (item is String) item];
}

int? _ageFrom(DateTime? birthDate, DateTime now) {
  if (birthDate == null) return null;

  int age = now.year - birthDate.year;
  final bool hasNotHadBirthdayYet =
      now.month < birthDate.month ||
      (now.month == birthDate.month && now.day < birthDate.day);
  if (hasNotHadBirthdayYet) age -= 1;
  return age;
}
