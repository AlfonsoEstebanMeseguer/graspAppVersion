import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grasp_mobile/core/theming/app_theme.dart';
import 'package:grasp_mobile/data/supabase/supabase_providers.dart';
import 'package:grasp_mobile/domain/profile/avatar_image_format.dart';
import 'package:grasp_mobile/data/profile/supabase_avatar_repository.dart';
import 'package:grasp_mobile/domain/profile/avatar_repository.dart';
import 'package:grasp_mobile/domain/profile/avatar_type.dart';
import 'package:grasp_mobile/domain/profile/image_compressor.dart';
import 'package:grasp_mobile/features/profile/presentation/widgets/avatar_selector.dart';
import 'package:grasp_mobile/features/profile/presentation/widgets/avatar_sheet.dart';

class _FakeAvatarRepository implements AvatarRepository {
  _FakeAvatarRepository({this.failWith});

  final Object? failWith;
  final List<AvatarType> presetsSet = <AvatarType>[];
  final List<String> mimesUploaded = <String>[];

  @override
  Future<void> setPreset(AvatarType preset) async {
    if (failWith != null) throw failWith!;
    presetsSet.add(preset);
  }

  @override
  Future<String> uploadPhoto(Uint8List imageBytes, String mimeType) async {
    if (failWith != null) throw failWith!;
    mimesUploaded.add(mimeType);
    return 'avatars/u/x.webp';
  }

  @override
  Future<String?> photoUrl(String userId) async => null;

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

/// Devuelve siempre un WebP válido del tamaño pedido, sin tocar ningún códec.
class _FakeCompressor implements ImageCompressor {
  _FakeCompressor({this.size = 1024});

  final int size;

  @override
  Future<CompressedImage> compress(
    Uint8List source, {
    required int maxSide,
    required int quality,
  }) async {
    final Uint8List b = Uint8List(size);
    b.setAll(0, <int>[0x52, 0x49, 0x46, 0x46]);
    b.setAll(8, <int>[0x57, 0x45, 0x42, 0x50]);
    return CompressedImage(bytes: b, format: AvatarImageFormat.webp);
  }
}

Future<void> _pumpSheet(
  WidgetTester tester, {
  required AvatarRepository repository,
  ImageCompressor? compressor,
  PickImageBytes? pickImage,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        avatarRepositoryProvider.overrideWithValue(repository),
        imageCompressorProvider.overrideWithValue(compressor ?? _FakeCompressor()),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (BuildContext context) => TextButton(
              onPressed: () => AvatarSheet.show(
                context,
                pickImage: pickImage,
                // El recorte tiene sus propios tests (crop_geometry_test.dart); aqui se prueba
                // el flujo, y decodificar una imagen de verdad no aporta nada a eso.
                skipCrop: true,
              ),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('ofrece DOS acciones, no tres: no existe "quitar la foto"', (
    WidgetTester tester,
  ) async {
    await _pumpSheet(tester, repository: _FakeAvatarRepository());

    expect(find.text('Elegir un avatar'), findsOneWidget);
    expect(find.text('Subir una foto'), findsOneWidget);
    // El backend exige exactamente uno de photo_path o preset: no hay operacion de quitar.
    expect(find.textContaining('Quitar'), findsNothing);
    expect(find.textContaining('Eliminar'), findsNothing);
  });

  testWidgets('"Elegir un avatar" abre la grilla de predeterminados', (
    WidgetTester tester,
  ) async {
    await _pumpSheet(tester, repository: _FakeAvatarRepository());

    expect(find.byType(AvatarSelector), findsNothing);
    await tester.tap(find.text('Elegir un avatar'));
    await tester.pumpAndSettle();

    expect(find.byType(AvatarSelector), findsOneWidget);
  });

  testWidgets('elegir un predeterminado lo manda al repositorio y cierra', (
    WidgetTester tester,
  ) async {
    final _FakeAvatarRepository repo = _FakeAvatarRepository();
    await _pumpSheet(tester, repository: repo);

    await tester.tap(find.text('Elegir un avatar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AvatarType.gym.label));
    await tester.pumpAndSettle();

    expect(repo.presetsSet, <AvatarType>[AvatarType.gym]);
    expect(find.text('Subir una foto'), findsNothing); // la hoja se cerró
  });

  testWidgets('un fallo se enseña DENTRO de la hoja, sin cerrarla', (
    WidgetTester tester,
  ) async {
    final _FakeAvatarRepository repo = _FakeAvatarRepository(
      failWith: const AvatarException('No se pudo cambiar el avatar.'),
    );
    await _pumpSheet(tester, repository: repo);

    await tester.tap(find.text('Elegir un avatar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AvatarType.gym.label));
    await tester.pumpAndSettle();

    // Cerrar ante un error obligaria a rehacer todo el recorrido para reintentar.
    expect(find.text('No se pudo cambiar el avatar.'), findsOneWidget);
    expect(find.byType(AvatarSelector), findsOneWidget);
  });

  testWidgets('subir una foto declara el mime del formato REALMENTE producido', (
    WidgetTester tester,
  ) async {
    final _FakeAvatarRepository repo = _FakeAvatarRepository();
    await _pumpSheet(
      tester,
      repository: repo,
      pickImage: () async => Uint8List(64),
    );

    await tester.tap(find.text('Subir una foto'));
    await tester.pumpAndSettle();

    // El compresor falso produce WebP, asi que se declara webp — nunca una constante.
    expect(repo.mimesUploaded, <String>['image/webp']);
  });

  testWidgets('cancelar el selector no es un error y no sube nada', (
    WidgetTester tester,
  ) async {
    final _FakeAvatarRepository repo = _FakeAvatarRepository();
    await _pumpSheet(tester, repository: repo, pickImage: () async => null);

    await tester.tap(find.text('Subir una foto'));
    await tester.pumpAndSettle();

    expect(repo.mimesUploaded, isEmpty);
    expect(find.text('Subir una foto'), findsOneWidget); // sigue abierta
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('una imagen que no cabe da un mensaje legible, no un error crudo', (
    WidgetTester tester,
  ) async {
    await _pumpSheet(
      tester,
      repository: _FakeAvatarRepository(),
      compressor: _FakeCompressor(size: 500 * 1024),
      pickImage: () async => Uint8List(64),
    );

    await tester.tap(find.text('Subir una foto'));
    await tester.pumpAndSettle();

    expect(find.textContaining('no se puede subir'), findsOneWidget);
  });
}
