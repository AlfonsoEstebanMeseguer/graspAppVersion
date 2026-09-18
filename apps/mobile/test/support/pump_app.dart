import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grasp_mobile/core/theming/app_theme.dart';
import 'package:grasp_mobile/data/supabase/supabase_providers.dart';
import 'package:grasp_mobile/domain/auth/auth_repository.dart';

import 'fake_auth_repository.dart';

/// Monta un widget con el tema real y el repositorio de auth sustituido.
///
/// El tema se monta con `GraspMotion.still()`: las pantallas tienen animaciones
/// en bucle (la marca "respira", la escena deriva) y con ellas activas
/// `pumpAndSettle` no termina nunca. Es la razón de que `GraspMotion` sea una
/// `ThemeExtension` y no constantes sueltas.
Future<FakeAuthRepository> pumpApp(
  WidgetTester tester,
  Widget child, {
  FakeAuthRepository? repository,
}) async {
  final FakeAuthRepository fake = repository ?? FakeAuthRepository();
  addTearDown(fake.dispose);

  final ThemeData theme = AppTheme.light().copyWith(
    extensions: const <ThemeExtension<dynamic>>[GraspMotion.still()],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        authRepositoryProvider.overrideWith((Ref ref) => fake),
      ],
      child: MaterialApp(theme: theme, home: child),
    ),
  );
  await tester.pump();

  return fake;
}

/// Igual que [pumpApp] pero devolviendo también el `ProviderContainer`, para
/// poder leer el estado de un controlador desde el test.
extension WidgetTesterX on WidgetTester {
  ProviderContainer containerOf(Finder finder) =>
      ProviderScope.containerOf(element(finder));
}

/// Repositorio de auth como `Provider`, tipado para los `overrides`.
typedef AuthRepositoryProvider = Provider<AuthRepository>;
