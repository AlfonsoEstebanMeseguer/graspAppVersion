import 'package:flutter_test/flutter_test.dart';
import 'package:grasp_mobile/features/messages/presentation/widgets/conversation_tile.dart';

/// Tests de la hora de la derecha de la fila (§8.2).
///
/// Se distingue hoy / ayer / esta semana / más atrás porque **«19:24» a secas en una conversación
/// de hace tres días se lee como de hoy**, y eso hace que la bandeja parezca activa cuando no lo
/// está.
void main() {
  // Miércoles 26 de agosto de 2026, 14:00.
  final DateTime ahora = DateTime(2026, 8, 26, 14, 0);

  test('hoy: solo la hora, con dos dígitos', () {
    expect(formatInboxTimestamp(ahora, DateTime(2026, 8, 26, 19, 24)), '19:24');
    expect(formatInboxTimestamp(ahora, DateTime(2026, 8, 26, 9, 5)), '09:05');
  });

  test('hoy incluye la madrugada, no solo lo anterior a «ahora»', () {
    // Lo que decide es el DÍA, no si ya pasó la hora: un mensaje de las 23:50 de hoy sigue siendo
    // de hoy aunque «ahora» sean las 14:00 (pasa con el reloj del servidor ligeramente adelantado).
    expect(formatInboxTimestamp(ahora, DateTime(2026, 8, 26, 23, 50)), '23:50');
  });

  test('ayer lo dice con palabras', () {
    expect(formatInboxTimestamp(ahora, DateTime(2026, 8, 25, 19, 24)), 'Ayer');
  });

  test('dentro de la semana, el día', () {
    // Domingo 23, lunes 24: los dos a menos de 7 días.
    expect(formatInboxTimestamp(ahora, DateTime(2026, 8, 24, 10, 0)), 'Lun');
    expect(formatInboxTimestamp(ahora, DateTime(2026, 8, 23, 10, 0)), 'Dom');
  });

  test('a partir de una semana, la fecha', () {
    expect(formatInboxTimestamp(ahora, DateTime(2026, 8, 19, 10, 0)), '19/08');
    expect(formatInboxTimestamp(ahora, DateTime(2026, 7, 4, 10, 0)), '04/07');
  });

  test('los cuatro formatos son distintos entre sí', () {
    // Sin esto, una implementación que devolviera siempre la hora pasaría los tres primeros tests
    // si las horas coincidieran por casualidad.
    final Set<String> formatos = <String>{
      formatInboxTimestamp(ahora, DateTime(2026, 8, 26, 10, 0)),
      formatInboxTimestamp(ahora, DateTime(2026, 8, 25, 10, 0)),
      formatInboxTimestamp(ahora, DateTime(2026, 8, 24, 10, 0)),
      formatInboxTimestamp(ahora, DateTime(2026, 8, 1, 10, 0)),
    };
    expect(formatos.length, 4);
  });
}
