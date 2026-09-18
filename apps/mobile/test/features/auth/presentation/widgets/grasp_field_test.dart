import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grasp_mobile/features/auth/presentation/widgets/grasp_field.dart';

/// Guarda la barrera de edad del Art. 8 RGPD (hallazgo H-RV-01): el selector
/// de fecha de nacimiento de `GraspDateField` no puede ofrecer una fecha que
/// implique menos de 13 años, ni una de más de 120. Antes de este fix el
/// widget montaba `showDatePicker` con `lastDate: DateTime.now()`, así que
/// alguien podía registrarse con la fecha de hoy como nacimiento.
void main() {
  Future<void> pumpDateField(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GraspDateField(
            label: 'Tu fecha de nacimiento',
            controller: TextEditingController(),
          ),
        ),
      ),
    );
  }

  Future<DatePickerDialog> openDatePicker(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Elegir fecha en el calendario'));
    await tester.pumpAndSettle();
    return tester.widget<DatePickerDialog>(find.byType(DatePickerDialog));
  }

  testWidgets(
    'la fecha máxima del selector es hoy menos 13 años, no hoy',
    (WidgetTester tester) async {
      await pumpDateField(tester);
      final DatePickerDialog dialog = await openDatePicker(tester);

      final DateTime now = DateTime.now();
      final DateTime expectedMax = DateTime(now.year - 13, now.month, now.day);

      expect(dialog.lastDate, expectedMax);
      // Con el bug original (`lastDate: DateTime.now()`) esto habría dado
      // `true`: hoy es una fecha de nacimiento válida.
      expect(dialog.lastDate.isBefore(now), isTrue);
    },
  );

  testWidgets(
    'la fecha mínima del selector es hoy menos 120 años',
    (WidgetTester tester) async {
      await pumpDateField(tester);
      final DatePickerDialog dialog = await openDatePicker(tester);

      final DateTime now = DateTime.now();
      final DateTime expectedMin = DateTime(now.year - 120, now.month, now.day);

      expect(dialog.firstDate, expectedMin);
    },
  );

  testWidgets(
    'la fecha inicial del selector cae dentro del rango permitido',
    (WidgetTester tester) async {
      await pumpDateField(tester);
      final DatePickerDialog dialog = await openDatePicker(tester);

      expect(dialog.initialDate!.isAfter(dialog.firstDate), isTrue);
      expect(dialog.initialDate!.isBefore(dialog.lastDate.add(const Duration(days: 1))), isTrue);
    },
  );
}
