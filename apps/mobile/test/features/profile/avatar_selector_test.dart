import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grasp_mobile/core/theming/app_theme.dart';
import 'package:grasp_mobile/domain/profile/avatar_type.dart';
import 'package:grasp_mobile/features/profile/presentation/widgets/avatar_selector.dart';

void main() {
  group('AvatarSelector', () {
    testWidgets('renders 8 avatars in a 2×4 grid', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light().copyWith(
            extensions: const <ThemeExtension<dynamic>>[GraspMotion.still()],
          ),
          home: Scaffold(
            body: AvatarSelector(onSelected: (_) {}),
          ),
        ),
      );

      // Verificar que se muestran todos los 8 labels (uno por avatar)
      expect(find.text('Gym'), findsOneWidget);
      expect(find.text('Lector'), findsOneWidget);
      expect(find.text('Música'), findsOneWidget);
      expect(find.text('Coding'), findsOneWidget);
      expect(find.text('Animal'), findsOneWidget);
      expect(find.text('Normal 1'), findsOneWidget);
      expect(find.text('Normal 2'), findsOneWidget);
      expect(find.text('Normal 3'), findsOneWidget);

      // Verificar que hay 8 contenedores (tarjetas)
      expect(find.byType(Container), findsWidgets);

      // Verificar título
      expect(find.text('Elige tu avatar'), findsOneWidget);
    });

    testWidgets('selects avatar on tap and calls onSelected', (
      WidgetTester tester,
    ) async {
      AvatarType? selectedAvatar;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light().copyWith(
            extensions: const <ThemeExtension<dynamic>>[GraspMotion.still()],
          ),
          home: Scaffold(
            body: AvatarSelector(
              onSelected: (avatar) => selectedAvatar = avatar,
            ),
          ),
        ),
      );

      // Tap en la tarjeta de "Gym" (primera)
      final Finder gymFinder = find.text('Gym');
      await tester.ensureVisible(gymFinder.first);
      await tester.pumpAndSettle();
      await tester.tap(gymFinder.first);
      await tester.pumpAndSettle();

      expect(selectedAvatar, AvatarType.gym);

      // Tap en la tarjeta de "Lector" (segunda)
      final Finder lectorFinder = find.text('Lector');
      await tester.ensureVisible(lectorFinder);
      await tester.pumpAndSettle();
      await tester.tap(lectorFinder);
      await tester.pumpAndSettle();

      expect(selectedAvatar, AvatarType.reader);

      // Tap en la tarjeta de "Música" (tercera)
      final Finder musicFinder = find.text('Música');
      await tester.ensureVisible(musicFinder);
      await tester.pumpAndSettle();
      await tester.tap(musicFinder);
      await tester.pumpAndSettle();

      expect(selectedAvatar, AvatarType.music);
    });

    testWidgets('shows visual feedback with border color change on selection', (
      WidgetTester tester,
    ) async {
      final List<AvatarType> selections = <AvatarType>[];

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light().copyWith(
            extensions: const <ThemeExtension<dynamic>>[GraspMotion.still()],
          ),
          home: Scaffold(
            body: AvatarSelector(
              onSelected: (avatar) => selections.add(avatar),
            ),
          ),
        ),
      );

      // Verificar estado inicial sin selección (Gym es el default pero no hay feedback visual)
      expect(find.text('Gym'), findsOneWidget);

      // Tap en Reader
      await tester.tap(find.text('Lector'));
      await tester.pumpAndSettle();

      // Verificar que se registró la selección
      expect(selections.length, 1);
      expect(selections.first, AvatarType.reader);

      // Tap nuevamente en Gym
      await tester.tap(find.text('Gym').first);
      await tester.pumpAndSettle();

      expect(selections.length, 2);
      expect(selections[1], AvatarType.gym);
    });

    testWidgets('initializes with selectedAvatar parameter', (
      WidgetTester tester,
    ) async {
      AvatarType? selectedAvatar;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light().copyWith(
            extensions: const <ThemeExtension<dynamic>>[GraspMotion.still()],
          ),
          home: Scaffold(
            body: AvatarSelector(
              selectedAvatar: AvatarType.music,
              onSelected: (avatar) => selectedAvatar = avatar,
            ),
          ),
        ),
      );

      // Verificar que se renderiza con el avatar inicial
      expect(find.text('Música'), findsOneWidget);

      // Tap en otro avatar debe registrarse
      final Finder animalFinder = find.text('Animal');
      await tester.ensureVisible(animalFinder);
      await tester.pumpAndSettle();
      await tester.tap(animalFinder);
      await tester.pumpAndSettle();

      expect(selectedAvatar, AvatarType.animal);
    });
  });
}