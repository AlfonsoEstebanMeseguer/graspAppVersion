import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grasp_mobile/core/theming/app_theme.dart';
import 'package:grasp_mobile/data/supabase/supabase_providers.dart';
import 'package:grasp_mobile/domain/profile/avatar_repository.dart';
import 'package:grasp_mobile/domain/profile/avatar_type.dart';
import 'package:grasp_mobile/domain/profile/profile.dart';
import 'package:grasp_mobile/features/profile/presentation/widgets/profile_avatar.dart';

const String _userId = 'da2de860-429c-4b9f-8458-feb74d6b5a6a';

class _CountingAvatarRepository implements AvatarRepository {
  int photoUrlCalls = 0;

  @override
  Future<String?> photoUrl(String userId) async {
    photoUrlCalls++;
    // Cada llamada devolvería una URL DISTINTA en producción (la firma lleva la hora).
    return 'https://r2.test/foto?firma=$photoUrlCalls';
  }

  @override
  Future<void> setPreset(AvatarType preset) async {}

  @override
  Future<String> uploadPhoto(Uint8List imageBytes, String mimeType) async => '';

  @override
  Future<Map<String, String>> photoUrls(List<String> userIds) async {
    final Map<String, String> out = <String, String>{};
    for (final String id in userIds) {
      final String? url = await photoUrl(id);
      if (url != null) out[id] = url;
    }
    return out;
  }
}

Profile _profile({String? photoPath, AvatarType? preset, String? name}) {
  return Profile(
    userId: _userId,
    displayName: name ?? 'Alfonso',
    photoPath: photoPath,
    presetAvatar: preset,
  );
}

Future<void> _pump(
  WidgetTester tester,
  Profile profile, {
  AvatarRepository? repository,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        avatarRepositoryProvider.overrideWithValue(
          repository ?? _CountingAvatarRepository(),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: ProfileAvatar(profile: profile)),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('sin foto ni preset se pinta la inicial del nombre', (
    WidgetTester tester,
  ) async {
    await _pump(tester, _profile());

    expect(find.text('A'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('sin nombre, la inicial es una interrogacion', (
    WidgetTester tester,
  ) async {
    await _pump(tester, _profile(name: ''));

    expect(find.text('?'), findsOneWidget);
  });

  testWidgets('con preset se pinta el asset local, sin pedir ninguna URL', (
    WidgetTester tester,
  ) async {
    final _CountingAvatarRepository repo = _CountingAvatarRepository();
    await _pump(tester, _profile(preset: AvatarType.gym), repository: repo);

    final Image image = tester.widget<Image>(find.byType(Image));
    expect(image.image, isA<AssetImage>());
    expect((image.image as AssetImage).assetName, AvatarType.gym.assetPath);
    // Los 8 predeterminados son assets locales: no existen en R2 y no se firma nada.
    expect(repo.photoUrlCalls, 0);
  });

  testWidgets('con photo_path se pide la URL firmada', (
    WidgetTester tester,
  ) async {
    final _CountingAvatarRepository repo = _CountingAvatarRepository();
    await _pump(
      tester,
      _profile(photoPath: 'avatars/$_userId/a.webp'),
      repository: repo,
    );
    await tester.pump();

    expect(repo.photoUrlCalls, 1);
  });

  // ESTE es el test de la caché. Sin ella, cada `build` pediría una firma nueva, y como la URL
  // cambia en cada llamada, `Image.network` volvería a descargar los bytes de una foto ya vista.
  testWidgets('repintar NO vuelve a pedir la firma de la misma foto', (
    WidgetTester tester,
  ) async {
    final _CountingAvatarRepository repo = _CountingAvatarRepository();
    final Profile profile = _profile(photoPath: 'avatars/$_userId/a.webp');

    await _pump(tester, profile, repository: repo);
    await tester.pump();
    expect(repo.photoUrlCalls, 1);

    // Varios repintados de la misma foto.
    for (int i = 0; i < 3; i++) {
      await tester.pump();
    }

    expect(repo.photoUrlCalls, 1, reason: 'la URL tiene que venir de la cache');
  });

  testWidgets('si no se puede firmar, cae a la inicial y no rompe el perfil', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      _profile(photoPath: 'avatars/$_userId/a.webp'),
      repository: _FailingAvatarRepository(),
    );
    await tester.pump();

    expect(find.text('A'), findsOneWidget);
  });
}

class _FailingAvatarRepository implements AvatarRepository {
  @override
  Future<String?> photoUrl(String userId) async =>
      throw Exception('R2 caido');

  @override
  Future<void> setPreset(AvatarType preset) async {}

  @override
  Future<String> uploadPhoto(Uint8List imageBytes, String mimeType) async => '';

  @override
  Future<Map<String, String>> photoUrls(List<String> userIds) async {
    final Map<String, String> out = <String, String>{};
    for (final String id in userIds) {
      final String? url = await photoUrl(id);
      if (url != null) out[id] = url;
    }
    return out;
  }
}
