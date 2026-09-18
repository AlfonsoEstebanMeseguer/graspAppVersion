import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:grasp_mobile/domain/social/follow_edge.dart';

/// Tests de [FollowState], y en particular del **doble vocabulario** del backend.
void main() {
  group('los dos literales que significan «ya le sigo»', () {
    test('«following», el que manda connect-tag-lookup', () {
      expect(FollowState.fromWire('following'), FollowState.following);
    });

    test('«accepted», el que manda follow-toggle', () {
      // `follow-toggle` devuelve el valor CRUDO de `user_follows.status`, que es `accepted`;
      // `connect-tag-lookup` lo traduce antes a `following`. Sin este alias, aceptar una solicitud
      // dejaba el botón diciendo `Seguir` otra vez, y sin ningún error de por medio.
      expect(FollowState.fromWire('accepted'), FollowState.following);
    });

    test('los dos dan EXACTAMENTE el mismo estado', () {
      expect(FollowState.fromWire('accepted'), FollowState.fromWire('following'));
    });
  });

  group('el resto de valores', () {
    test('«none» y «pending» se resuelven', () {
      expect(FollowState.fromWire('none'), FollowState.none);
      expect(FollowState.fromWire('pending'), FollowState.pending);
    });

    test('un valor desconocido cae al estado MENOS afirmativo', () {
      // Enseñar `Seguir` de más es recuperable: la llamada es un no-op por forma. Enseñar
      // `Siguiendo` de más miente sobre una relación que quizá no existe.
      expect(FollowState.fromWire('lo_que_sea'), FollowState.none);
      expect(FollowState.fromWire(null), FollowState.none);
      expect(FollowState.fromWire(''), FollowState.none);
    });
  });

  group('el alias sigue haciendo falta (si el backend cambia, este test avisa)', () {
    test('follow-toggle sigue declarando «accepted» en su tipo de salida', () {
      // Este alias existe por una asimetría del backend, no por gusto. Si algún día
      // `follow-toggle` se alinea con `connect-lookup` y deja de emitir `accepted`, el alias pasa a
      // ser código muerto — y conviene enterarse aquí en vez de arrastrarlo para siempre.
      final File source = File(
        '../backend/supabase/functions/follow-toggle/index.ts',
      );
      expect(source.existsSync(), isTrue, reason: 'No se encuentra follow-toggle/index.ts');
      expect(
        source.readAsStringSync(),
        contains('"none" | "pending" | "accepted"'),
        reason:
            'follow-toggle ya no declara «accepted». Si dejó de emitirlo, el alias de '
            'FollowState.fromWire sobra; compruébalo antes de quitarlo.',
      );
    });

    test('connect-lookup sigue declarando «following»', () {
      final File source = File(
        '../backend/supabase/functions/_shared/connect-lookup.ts',
      );
      expect(source.existsSync(), isTrue);
      expect(
        source.readAsStringSync(),
        contains('"none" | "pending" | "following"'),
      );
    });
  });
}
