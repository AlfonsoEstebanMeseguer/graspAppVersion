import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grasp_mobile/core/theming/app_theme.dart';
import 'package:grasp_mobile/data/supabase/supabase_providers.dart';
import 'package:grasp_mobile/domain/profile/avatar_repository.dart';
import 'package:grasp_mobile/domain/profile/avatar_type.dart';
import 'package:grasp_mobile/domain/profile/profile.dart';
import 'package:grasp_mobile/features/profile/presentation/widgets/avatar_viewer.dart';
import 'package:grasp_mobile/features/profile/presentation/widgets/profile_avatar.dart';
import 'package:grasp_mobile/features/profile/presentation/widgets/profile_header.dart';

class _NoPhotoRepository implements AvatarRepository {
  @override
  Future<String?> photoUrl(String userId) async => null;
  @override
  Future<void> setPreset(AvatarType preset) async {}
  @override
  Future<String> uploadPhoto(Uint8List b, String m) async => '';

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

final Profile _profile = Profile(
  userId: 'da2de860-429c-4b9f-8458-feb74d6b5a6a',
  displayName: 'Alfonso',
  presetAvatar: AvatarType.gym,
);

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        avatarRepositoryProvider.overrideWithValue(_NoPhotoRepository()),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: child),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('el visor enseña el avatar y el nombre', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      Builder(
        builder: (BuildContext context) => TextButton(
          onPressed: () => AvatarViewer.show(context, _profile),
          child: const Text('abrir'),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    expect(find.byType(ProfileAvatar), findsOneWidget);
    expect(find.text('Alfonso'), findsOneWidget);
    // Se puede acercar: una foto recortada a un círculo pequeño esconde detalle.
    expect(find.byType(InteractiveViewer), findsOneWidget);
  });

  // La foto se sube recortada a un CUADRADO: el circulo del perfil se come las esquinas, asi que
  // ampliarla como circulo no ensenaria nada que no se viera ya.
  testWidgets('al ampliar se ve CUADRADO, no circulo', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      Builder(
        builder: (BuildContext context) => TextButton(
          onPressed: () => AvatarViewer.show(context, _profile),
          child: const Text('abrir'),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    final ProfileAvatar avatar = tester.widget<ProfileAvatar>(
      find.byType(ProfileAvatar),
    );
    expect(avatar.shape, AvatarShape.rounded);
    expect(find.byType(ClipRRect), findsWidgets);
  });

  // El perfil SI es un circulo, y tiene que seguir siendolo.
  testWidgets('en el perfil el avatar sigue siendo un circulo', (
    WidgetTester tester,
  ) async {
    await _pump(tester, ProfileAvatar(profile: _profile));

    final ProfileAvatar avatar = tester.widget<ProfileAvatar>(
      find.byType(ProfileAvatar),
    );
    expect(avatar.shape, AvatarShape.circle);
    expect(find.byType(ClipOval), findsOneWidget);
  });

  // Con el valor por defecto (200) cada muesca de rueda salta casi un 40%, que es lo que se
  // sentia "a escalones" en vez de progresivo.
  testWidgets('el zoom con rueda es progresivo, no a saltos', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      Builder(
        builder: (BuildContext context) => TextButton(
          onPressed: () => AvatarViewer.show(context, _profile),
          child: const Text('abrir'),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    final InteractiveViewer viewer = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    expect(
      viewer.scaleFactor,
      greaterThanOrEqualTo(800),
      reason: 'por debajo de esto el zoom vuelve a ir a saltos',
    );
  });

  testWidgets('se cierra con la equis', (WidgetTester tester) async {
    await _pump(
      tester,
      Builder(
        builder: (BuildContext context) => TextButton(
          onPressed: () => AvatarViewer.show(context, _profile),
          child: const Text('abrir'),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();

    expect(find.byType(AvatarViewer), findsNothing);
  });

  // ESTE es el requisito: tocar la foto la MIRA, tocar el lápiz la CAMBIA.
  // Si los dos gestos acabaran en el mismo sitio, uno de los dos sobra.
  testWidgets('la foto y el lapiz son gestos distintos', (
    WidgetTester tester,
  ) async {
    int mirar = 0;
    int cambiar = 0;

    await _pump(
      tester,
      ProfileHeader(
        profile: _profile,
        birthDateMonthDay: null,
        onTapEdit: () {},
        onTapPhoto: () => cambiar++,
        onTapAvatar: () => mirar++,
      ),
    );

    await tester.tap(find.byType(ProfileAvatar));
    await tester.pump();
    expect(mirar, 1, reason: 'tocar la foto la mira');
    expect(cambiar, 0, reason: 'tocar la foto NO abre el menu');

    await tester.tap(find.byIcon(Icons.edit_rounded));
    await tester.pump();
    expect(cambiar, 1, reason: 'el lapiz abre el menu');
    expect(mirar, 1, reason: 'el lapiz NO abre el visor');
  });
}
