import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:grasp_mobile/domain/social/message_input_state.dart';

/// Tests de [MessageInputState] — los estados del input del §9.2.
///
/// Este fichero es donde `RN-23` se sostiene o se pierde en el cliente. El backend ya se encarga de
/// que un bloqueo y un cupo agotado salgan **idénticos campo a campo** (ADR 0022,
/// `_shared/messaging-limits.ts` no tiene variante pública para el bloqueo). Lo que se prueba aquí
/// es que el cliente **no reintroduzca** la distinción al interpretarlos.
Map<String, dynamic> _input({
  required bool canSend,
  String? notice,
  int? messagesLeft,
  bool requestActions = false,
}) => <String, dynamic>{
  'can_send': canSend,
  'input_notice': notice,
  'messages_left': messagesLeft,
  'request_actions': requestActions,
};

void main() {
  // Las cinco filas de la tabla del §9.2, tal y como las documenta `docs/api-contracts.md`.
  final Map<String, dynamic> filaAceptada = _input(canSend: true);
  final Map<String, dynamic> filaConRestantes = _input(
    canSend: true,
    messagesLeft: 3,
  );
  final Map<String, dynamic> filaCupoAgotado = _input(
    canSend: false,
    notice: kMessageInputNotice,
    messagesLeft: 0,
  );
  final Map<String, dynamic> filaSolicitudRecibida = _input(
    canSend: true,
    requestActions: true,
  );
  final Map<String, dynamic> filaBloqueado = _input(
    canSend: false,
    notice: kMessageInputNotice,
    messagesLeft: 0,
  );

  group('§9.2 — cada fila de la tabla da su estado', () {
    test('fila 1, conversación aceptada: se escribe sin tope', () {
      final MessageInputState state = MessageInputState.fromJson(filaAceptada);
      expect(state, isA<MessageInputOpen>());
      expect(state.canType, isTrue);
    });

    test('fila 2, solicitud enviada con restantes: se escribe, con contador', () {
      final MessageInputState state = MessageInputState.fromJson(
        filaConRestantes,
      );
      expect(state, isA<MessageInputLimited>());
      expect((state as MessageInputLimited).messagesLeft, 3);
      expect(state.canType, isTrue);
    });

    test('fila 3, los 5 gastados: inerte con el aviso', () {
      final MessageInputState state = MessageInputState.fromJson(
        filaCupoAgotado,
      );
      expect(state, isA<MessageInputInert>());
      expect((state as MessageInputInert).notice, kMessageInputNotice);
      expect(state.canType, isFalse);
    });

    test('fila 4, solicitud recibida: las cuatro acciones en vez del input', () {
      final MessageInputState state = MessageInputState.fromJson(
        filaSolicitudRecibida,
      );
      expect(state, isA<MessageInputAwaitingDecision>());
      expect(state.canType, isFalse);
    });

    test('fila 5, bloqueado: inerte con el mismo aviso', () {
      final MessageInputState state = MessageInputState.fromJson(filaBloqueado);
      expect(state, isA<MessageInputInert>());
      expect((state as MessageInputInert).notice, kMessageInputNotice);
    });
  });

  group('RN-23 — nada distingue un bloqueo de un cupo agotado', () {
    test('las filas 3 y 5 producen estados IGUALES, no solo parecidos', () {
      // Si algún día alguien añade un campo `reason` a `MessageInputInert`, este test se pone rojo
      // antes de que llegue a una pantalla. Es la razón de que compare los objetos enteros y no
      // solo el texto.
      expect(
        MessageInputState.fromJson(filaCupoAgotado),
        MessageInputState.fromJson(filaBloqueado),
      );
    });

    test('el estado inerte no ofrece ninguna forma de saber el motivo', () {
      final MessageInputInert state =
          MessageInputState.fromJson(filaBloqueado) as MessageInputInert;
      // `toString()` es la vía por la que un motivo se cuela en un log y de ahí a una captura.
      expect(state.toString().toLowerCase(), isNot(contains('bloque')));
      expect(state.toString().toLowerCase(), isNot(contains('block')));
      expect(state.notice.toLowerCase(), isNot(contains('bloque')));
    });

    test(
      'can_send:false junto a request_actions:true NO pinta el aviso — sería un oráculo',
      () {
        // ESTE CASO YA NO LLEGA DESDE EL BACKEND, y el test se queda igual a propósito.
        //
        // Era un oráculo real: A manda solicitud a B y luego bloquea a B; B abría el hilo y recibía
        // `request_actions: true` junto a `can_send: false`. Para una solicitud RECIBIDA un
        // `can_send:false` SOLO puede venir de un bloqueo —el tope de RN-01 se le aplica a quien
        // pide entrar, no a quien contesta—, así que pintar el aviso le decía a B que le habían
        // bloqueado.
        //
        // El ADR 0025 (2026-08-26) lo cerró en el servidor: `messaging-view.ts` emite esa fila
        // constante. Esta comprobación se conserva como SEGUNDA CAPA — es barata, y si el backend
        // regresara, la pantalla seguiría sin delatar nada.
        //
        // `request_actions` gana: la pantalla queda idéntica a la de una solicitud normal.
        final MessageInputState state = MessageInputState.fromJson(
          _input(
            canSend: false,
            notice: kMessageInputNotice,
            messagesLeft: 0,
            requestActions: true,
          ),
        );
        expect(state, isA<MessageInputAwaitingDecision>());
        expect(
          state,
          MessageInputState.fromJson(filaSolicitudRecibida),
          reason:
              'Una solicitud recibida con bloqueo tiene que dar el MISMO estado que una sin '
              'bloqueo, o el estado del input delata el bloqueo (RN-23).',
        );
      },
    );
  });

  group('ADR 0022 — un solo texto, y es el del backend', () {
    test('la constante Dart es la misma cadena que INPUT_NOTICE_QUOTA en Deno', () {
      // El ADR 0022 exige UNA sola constante porque «dos literales pueden divergir al editarlos».
      // Dart y Deno no pueden compartir una, así que lo siguiente mejor es un test que compare las
      // dos fuentes: si alguien edita el texto del backend, esto se pone rojo.
      final File source = File(
        '../backend/supabase/functions/_shared/messaging-view.ts',
      );
      expect(source.existsSync(), isTrue, reason: 'No se encuentra messaging-view.ts');

      final RegExp literal = RegExp(
        r'export const INPUT_NOTICE_QUOTA\s*=\s*\n?\s*"([^"]*)"',
      );
      final RegExpMatch? match = literal.firstMatch(source.readAsStringSync());
      expect(
        match,
        isNotNull,
        reason: 'No se pudo extraer INPUT_NOTICE_QUOTA de messaging-view.ts',
      );
      expect(kMessageInputNotice, match!.group(1));
    });

    test('el literal retirado por el ADR 0022 no aparece en ninguna parte', () {
      expect(kMessageInputNotice, isNot(contains('No puedes enviar mensajes')));
    });
  });

  group('§9.2 fila 6 — conversación nueva desde Conectar', () {
    test('arranca con los 5 mensajes de RN-01, sin llamar al backend', () {
      // No hay conversación todavía, así que no hay `messaging-thread` que consultar: el estado se
      // construye en el cliente y tiene que coincidir con el que devolvería el backend tras el
      // primer mensaje.
      expect(
        MessageInputState.newConversation,
        const MessageInputLimited(5),
      );
    });
  });

  group('robustez del parseo', () {
    test('un `messages_left` ausente se trata como sin tope', () {
      expect(
        MessageInputState.fromJson(<String, dynamic>{'can_send': true}),
        isA<MessageInputOpen>(),
      );
    });

    test('sin aviso, un can_send:false cae al texto único y no a una cadena vacía', () {
      // Un input inerte con el aviso en blanco es un input roto: la persona no sabe qué pasa.
      final MessageInputState state = MessageInputState.fromJson(
        <String, dynamic>{'can_send': false},
      );
      expect((state as MessageInputInert).notice, kMessageInputNotice);
    });

    test('un JSON vacío falla cerrado: no se puede escribir', () {
      // Falla cerrado a propósito: ante la duda, no dejar escribir es recuperable; dejar escribir
      // cuando el backend lo iba a rechazar produce un 422 que la persona no entiende.
      expect(
        MessageInputState.fromJson(const <String, dynamic>{}),
        isA<MessageInputInert>(),
      );
    });
  });
}
