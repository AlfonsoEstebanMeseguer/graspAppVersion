import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grasp_mobile/features/profile/presentation/widgets/privacy_section.dart';

void main() {
  testWidgets('la tarjeta de Privacidad ofrece la entrada a Usuarios bloqueados', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Scaffold(body: PrivacySection())),
      ),
    );
    await tester.pump();

    // La lista de bloqueados vivio cinco dias en la base sin que nada la pintara. Este test es la
    // puerta de entrada: si alguien quita la fila, se entera.
    expect(find.byKey(PrivacySection.blockedEntryKey), findsOneWidget);
    expect(find.text(PrivacySection.blockedLabel), findsOneWidget);
  });
}
