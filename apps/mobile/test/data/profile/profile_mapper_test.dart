import 'package:flutter_test/flutter_test.dart';
import 'package:grasp_mobile/data/profile/profile_mapper.dart';
import 'package:grasp_mobile/domain/profile/avatar_type.dart';
import 'package:grasp_mobile/domain/profile/profile.dart';
import 'package:grasp_mobile/domain/profile/profile_badge.dart';

/// El mapeo fila→[Profile] vive fuera del repositorio precisamente para poder
/// probarse aquí: sin `SupabaseClient`, sin sesión y sin red.
void main() {
  const String userId = 'aaaaaaaa-1111-4111-8111-111111111111';

  group('mapProfileRows', () {
    test('copia las columnas de profiles al modelo', () {
      final Profile profile = mapProfileRows(
        userId: userId,
        publicRow: <String, dynamic>{
          'display_name': 'Alfonso',
          'level': 3,
          'xp': 250,
          'streak_days': 7,
          'rooms_joined_count': 12,
          'time_helping_seconds': 3600,
          'followers_count': 5,
          'following_count': 9,
        },
      );

      expect(profile.userId, userId);
      expect(profile.displayName, 'Alfonso');
      expect(profile.level, 3);
      expect(profile.xp, 250);
      expect(profile.streakDays, 7);
      expect(profile.roomsJoinedCount, 12);
      expect(profile.timeHelpingSeconds, 3600);
      expect(profile.followersCount, 5);
      expect(profile.followingCount, 9);
    });

    test('una fila sin numéricos cae a los valores por defecto, no a null', () {
      final Profile profile = mapProfileRows(
        userId: userId,
        publicRow: <String, dynamic>{'display_name': null},
      );

      expect(profile.level, 1);
      expect(profile.xp, 0);
      expect(profile.streakDays, 0);
      expect(profile.roomsJoinedCount, 0);
      expect(profile.timeHelpingSeconds, 0);
      expect(profile.followersCount, 0);
      expect(profile.followingCount, 0);
      expect(profile.badges, isEmpty);
      expect(profile.interests, isEmpty);
      expect(profile.privateAnswers, isEmpty);
    });

    test('sin fila privada no hay edad, ni género, ni país (y no revienta)', () {
      final Profile profile = mapProfileRows(
        userId: userId,
        publicRow: <String, dynamic>{},
        privateRow: null,
      );

      expect(profile.age, isNull);
      expect(profile.birthDate, isNull);
      expect(profile.gender, isNull);
      expect(profile.country, isNull);
    });

    test('la edad se calcula contra el `now` que se le pasa', () {
      final Profile profile = mapProfileRows(
        userId: userId,
        publicRow: <String, dynamic>{},
        privateRow: <String, dynamic>{
          'birth_date': '1990-06-15',
          'gender': 'male',
          'country': 'ES',
        },
        now: DateTime(2026, 6, 14),
      );

      // Un día antes del cumpleaños: 35, no 36.
      expect(profile.age, 35);
      expect(profile.birthDate, DateTime(1990, 6, 15));
      expect(profile.gender, 'male');
      expect(profile.country, 'ES');
    });

    test('el día del cumpleaños ya cuenta el año', () {
      final Profile profile = mapProfileRows(
        userId: userId,
        publicRow: <String, dynamic>{},
        privateRow: <String, dynamic>{'birth_date': '1990-06-15'},
        now: DateTime(2026, 6, 15),
      );

      expect(profile.age, 36);
    });

    test('una fecha de nacimiento ilegible no rompe el perfil', () {
      final Profile profile = mapProfileRows(
        userId: userId,
        publicRow: <String, dynamic>{},
        privateRow: <String, dynamic>{'birth_date': 'ayer'},
        now: DateTime(2026, 6, 15),
      );

      expect(profile.age, isNull);
      expect(profile.birthDate, isNull);
    });

    test('las respuestas del onboarding se reparten entre intereses y privadas', () {
      final Profile profile = mapProfileRows(
        userId: userId,
        publicRow: <String, dynamic>{},
        onboardingRow: <String, dynamic>{
          'responses': <String, dynamic>{
            'interests': <dynamic>['ansiedad', 'duelo', 42],
            'situation': 'solo',
            'profile': 'oyente',
            'discovery': 'tiktok',
            'campo_que_la_app_no_conoce': 'se ignora',
          },
        },
      );

      // El 42 se cae: la lista es de strings o no es.
      expect(profile.interests, <String>['ansiedad', 'duelo']);
      expect(profile.privateAnswers, <String, String>{
        'situation': 'solo',
        'profile': 'oyente',
        'discovery': 'tiktok',
      });
    });

    test('sin fila de onboarding no hay intereses ni respuestas', () {
      final Profile profile = mapProfileRows(
        userId: userId,
        publicRow: <String, dynamic>{},
        onboardingRow: null,
      );

      expect(profile.interests, isEmpty);
      expect(profile.privateAnswers, isEmpty);
    });

    test('las insignias se pasan tal cual', () {
      // `description` e `icon` son `required` aunque sean nullable: hay que
      // pasarlos explícitamente.
      const List<ProfileBadge> badges = <ProfileBadge>[
        ProfileBadge(
          slug: 'primera-sala',
          name: 'Primera sala',
          description: null,
          icon: null,
          earned: true,
        ),
        ProfileBadge(
          slug: 'buen-oyente',
          name: 'Buen oyente',
          description: 'Escuchaste durante una hora',
          icon: 'hearing',
          earned: false,
        ),
      ];

      final Profile profile = mapProfileRows(
        userId: userId,
        publicRow: <String, dynamic>{},
        badges: badges,
      );

      expect(profile.badges, badges);
      expect(profile.earnedBadgesCount, 1);
    });
  });

  group('mapProfileRows: avatar', () {
    test('un preset_avatar conocido se resuelve al AvatarType', () {
      final Profile profile = mapProfileRows(
        userId: userId,
        publicRow: <String, dynamic>{'preset_avatar': 'gym', 'photo_path': null},
      );

      expect(profile.presetAvatar, AvatarType.gym);
      expect(profile.photoPath, isNull);
    });

    test('los ocho slugs del check se resuelven', () {
      for (final AvatarType avatar in AvatarType.values) {
        final Profile profile = mapProfileRows(
          userId: userId,
          publicRow: <String, dynamic>{'preset_avatar': avatar.slug},
        );
        expect(profile.presetAvatar, avatar, reason: 'slug ${avatar.slug}');
      }
    });

    test('un photo_path se expone tal cual, sin convertirlo en URL', () {
      const String key = 'avatars/aaaaaaaa-1111-4111-8111-111111111111/foto.webp';
      final Profile profile = mapProfileRows(
        userId: userId,
        publicRow: <String, dynamic>{'photo_path': key, 'preset_avatar': null},
      );

      // Es una CLAVE de R2, no una URL: la firma la da profile-photo-view-url.
      expect(profile.photoPath, key);
      expect(profile.presetAvatar, isNull);
    });

    test('sin avatar de ningún tipo, los dos campos son null', () {
      final Profile profile = mapProfileRows(
        userId: userId,
        publicRow: <String, dynamic>{},
      );

      expect(profile.photoPath, isNull);
      expect(profile.presetAvatar, isNull);
    });

    test('un slug que la app no conoce cae a null, no revienta', () {
      // App vieja contra backend nuevo: la UI cae al placeholder.
      final Profile profile = mapProfileRows(
        userId: userId,
        publicRow: <String, dynamic>{'preset_avatar': 'avatar_del_futuro'},
      );

      expect(profile.presetAvatar, isNull);
    });
  });

  group('profilePublicColumns: las columnas del avatar', () {
    test('pide photo_path y preset_avatar', () {
      expect(profilePublicColumns, contains('photo_path'));
      expect(profilePublicColumns, contains('preset_avatar'));
    });

    test('ya no pide photo_url, la columna legacy que nadie escribe', () {
      // `photo_path` contiene la subcadena `photo_p...`, así que se comprueba el
      // nombre exacto separado por comas y no un `contains` que daría falso
      // negativo.
      final Set<String> columnas = profilePublicColumns
          .split(',')
          .map((String c) => c.trim())
          .toSet();
      expect(columnas, isNot(contains('photo_url')));
    });
  });

  group('profilePublicColumns', () {
    test('pide las columnas que el mapeo lee', () {
      for (final String column in <String>[
        'display_name',
        'level',
        'xp',
        'streak_days',
        'rooms_joined_count',
        'time_helping_seconds',
        'followers_count',
        'following_count',
      ]) {
        expect(profilePublicColumns, contains(column));
      }
    });
  });
}
