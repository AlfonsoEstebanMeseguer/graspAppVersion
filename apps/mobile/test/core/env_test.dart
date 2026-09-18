import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:grasp_mobile/core/config/env.dart';

String _jwtWithRole(String role) {
  String segment(Map<String, dynamic> value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');

  return <String>[
    segment(<String, dynamic>{'alg': 'HS256', 'typ': 'JWT'}),
    segment(<String, dynamic>{'role': role}),
    'firma-irrelevante',
  ].join('.');
}

void main() {
  group('assertNoServiceRoleKey', () {
    // Invariante de la Sección 10: la clave que salta RLS no puede viajar en el
    // cliente. Preferimos romper el arranque en desarrollo a publicarla.
    test('rechaza la clave secreta nueva (sb_secret_)', () {
      expect(
        () => Env.assertNoServiceRoleKey('sb_secret_abc123'),
        throwsA(isA<StateError>()),
      );
    });

    test('rechaza un JWT con role service_role', () {
      expect(
        () => Env.assertNoServiceRoleKey(_jwtWithRole('service_role')),
        throwsA(isA<StateError>()),
      );
    });

    test('acepta la clave publicable nueva', () {
      expect(
        () => Env.assertNoServiceRoleKey('sb_publishable_abc123'),
        returnsNormally,
      );
    });

    test('acepta un JWT con role anon', () {
      expect(
        () => Env.assertNoServiceRoleKey(_jwtWithRole('anon')),
        returnsNormally,
      );
    });
  });

  group('assertIsApiUrl', () {
    // Copiar la URL del navegador en vez de la del API es el error más fácil de
    // cometer, y sin esta comprobación se manifiesta como fallos de red opacos.
    test('rechaza la URL del panel de control', () {
      expect(
        () =>
            Env.assertIsApiUrl('https://supabase.com/dashboard/project/abcdef'),
        throwsA(isA<StateError>()),
      );
    });

    test('acepta la URL del API del proyecto', () {
      expect(
        () => Env.assertIsApiUrl('https://abcdef.supabase.co'),
        returnsNormally,
      );
    });
  });
}
