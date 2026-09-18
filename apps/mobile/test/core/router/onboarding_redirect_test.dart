import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grasp_mobile/core/theming/app_theme.dart';
import 'package:grasp_mobile/core/router/app_router.dart';
import 'package:grasp_mobile/data/supabase/supabase_providers.dart';
import 'package:grasp_mobile/features/messages/presentation/messages_screen.dart';
import 'package:grasp_mobile/features/onboarding/presentation/onboarding_feed_screen.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_onboarding_repositories.dart';

/// Redirect `/onboarding` obligatorio tras el alta (`hasCompletedOnboardingProvider`,
/// ver `data/supabase/supabase_providers.dart`).
Future<FakeAuthRepository> _pumpRoutedApp(
  WidgetTester tester, {
  required bool hasCompletedOnboarding,
}) async {
  final FakeAuthRepository fake = FakeAuthRepository();
  addTearDown(fake.dispose);

  final ThemeData theme = AppTheme.light().copyWith(
    extensions: const <ThemeExtension<dynamic>>[GraspMotion.still()],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        authRepositoryProvider.overrideWith((Ref ref) => fake),
        hasCompletedOnboardingProvider.overrideWith(
          (Ref ref) async => hasCompletedOnboarding,
        ),
        onboardingCatalogsRepositoryProvider.overrideWithValue(
          FakeOnboardingCatalogsRepository(),
        ),
      ],
      child: Consumer(
        builder: (BuildContext context, WidgetRef ref, Widget? _) =>
            MaterialApp.router(theme: theme, routerConfig: ref.watch(routerProvider)),
      ),
    ),
  );
  await tester.pumpAndSettle();

  return fake;
}

void main() {
  group('redirección por onboarding', () {
    testWidgets('sin cuestionario completado, el login lleva a /onboarding', (
      WidgetTester tester,
    ) async {
      final FakeAuthRepository fake = await _pumpRoutedApp(
        tester,
        hasCompletedOnboarding: false,
      );

      fake.emitSignedIn('user-sin-onboarding');
      await tester.pumpAndSettle();

      expect(find.byType(OnboardingFeedScreen), findsOneWidget);
      expect(find.byType(MessagesScreen), findsNothing);
    });

    testWidgets('con cuestionario completado, el login lleva a /home', (
      WidgetTester tester,
    ) async {
      final FakeAuthRepository fake = await _pumpRoutedApp(
        tester,
        hasCompletedOnboarding: true,
      );

      fake.emitSignedIn('user-con-onboarding');
      await tester.pumpAndSettle();

      expect(find.byType(MessagesScreen), findsOneWidget);
      expect(find.byType(OnboardingFeedScreen), findsNothing);
    });
  });
}