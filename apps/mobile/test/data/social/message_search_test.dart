import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:grasp_mobile/data/social/message_search.dart';

/// Tests del espejo Dart de `_shared/text-search.ts` (§9.4).
///
/// **Por qué un espejo se prueba distinto que un módulo normal.** Lo que importa aquí no es que
/// «funcione», es que **coincida con el original byte a byte en los offsets**: el backend calcula
/// las coincidencias y el cliente resalta dentro de la burbuja, y el propio `text-search.ts`
/// advierte de que *«dos normalizaciones distintas a cada lado desplazan el resaltado»*. Un test
/// que solo comprobara «encuentra "cancion" en "Canción"» pasaría con una implementación que
/// devolviera offsets desplazados, que es justo el fallo que hay que impedir.
///
/// Por eso hay dos bloques:
///   1. Casos escritos a mano, que fijan las reglas una a una.
///   2. El **fixture dorado**, generado por el `text-search.ts` de verdad ejecutándose en Deno. Ése
///      es el que prueba que esto es un espejo y no una reimplementación parecida.
void main() {
  group('normalizeForSearch', () {
    test('quita diacríticos compuestos y baja a minúsculas', () {
      expect(normalizeForSearch('Canción'), 'cancion');
      expect(normalizeForSearch('ÁÉÍÓÚÜÑ'), 'aeiouun');
    });

    test('quita diacríticos ya descompuestos', () {
      // c a f e + U+0301 (acento combinante), que es como llega un texto en NFD.
      expect(normalizeForSearch('café'), 'cafe');
    });

    test('deja intacto lo que no lleva diacrítico', () {
      expect(normalizeForSearch('hola 123 🎵'), 'hola 123 🎵');
    });
  });

  group('findMatches — lo que pide el plan: «Canción»/«cancion» en los dos sentidos', () {
    test('busca sin acento un texto con acento', () {
      expect(findMatches('Canción', 'cancion'), <MatchOffset>[
        const MatchOffset(0, 7),
      ]);
    });

    test('busca con acento un texto sin acento', () {
      expect(findMatches('cancion', 'Canción'), <MatchOffset>[
        const MatchOffset(0, 7),
      ]);
    });

    test('es insensible a mayúsculas', () {
      expect(findMatches('HOLA hola HoLa', 'hola'), <MatchOffset>[
        const MatchOffset(0, 4),
        const MatchOffset(5, 9),
        const MatchOffset(10, 14),
      ]);
    });
  });

  group('findMatches — los offsets son del texto ORIGINAL', () {
    test('un acento anterior no desplaza el offset', () {
      // Si los offsets salieran del texto NORMALIZADO daría lo mismo aquí, porque «ó» compuesta
      // ocupa una unidad UTF-16 tanto antes como después de normalizar. El caso que discrimina es
      // el de abajo, con el texto descompuesto.
      expect(findMatches('canción bonita', 'bonita'), <MatchOffset>[
        const MatchOffset(8, 14),
      ]);
    });

    test('con acentos DESCOMPUESTOS antes, el offset sigue siendo del original', () {
      // "cancio" + U+0301 + "n bonita": 8 unidades UTF-16 antes de «bonita» + el combinante = 9.
      // Una implementación que indexara sobre el normalizado diría 8 y resaltaría "bonit".
      const String haystack = 'canción bonita';
      expect(findMatches(haystack, 'bonita'), <MatchOffset>[
        const MatchOffset(9, 15),
      ]);
      expect(haystack.substring(9, 15), 'bonita');
    });

    test('un emoji antes desplaza dos unidades UTF-16, no una', () {
      // 🎵 es un par suplente: 2 unidades UTF-16. Recorrer por puntos de código y contar 1 es el
      // fallo clásico de este fichero.
      const String haystack = '🎵Canción';
      final List<MatchOffset> matches = findMatches(haystack, 'cancion');
      expect(matches, <MatchOffset>[const MatchOffset(2, 9)]);
      expect(haystack.substring(2, 9), 'Canción');
    });
  });

  group('findMatches — la coincidencia se traga el acento descompuesto que la sigue', () {
    test('«cafe» sobre «café» descompuesto resalta también la tilde', () {
      // Sin esto el cliente pintaría "cafe" resaltado y una tilde suelta sin resaltar justo encima.
      const String haystack = 'café';
      expect(findMatches(haystack, 'cafe'), <MatchOffset>[
        const MatchOffset(0, 5),
      ]);
      expect(haystack.substring(0, 5), haystack);
    });

    test('se traga varios combinantes apilados sobre la misma letra', () {
      const String haystack = 'café̈';
      expect(findMatches(haystack, 'cafe'), <MatchOffset>[
        const MatchOffset(0, 6),
      ]);
    });
  });

  group('findMatches — casos que cuelgan o revientan si se hacen mal', () {
    test('aguja vacía devuelve vacío en vez de colgarse', () {
      // `indexOf("")` devuelve la posición de partida SIEMPRE: sin la guarda, el bucle no termina.
      expect(findMatches('lo que sea', ''), isEmpty);
    });

    test('aguja de solo espacios devuelve vacío', () {
      expect(findMatches('lo que sea', '   '), isEmpty);
    });

    test('aguja de un acento suelto (normaliza a nada) devuelve vacío', () {
      expect(findMatches('lo que sea', '́'), isEmpty);
    });

    test('pajar vacío devuelve vacío', () {
      expect(findMatches('', 'hola'), isEmpty);
    });

    test('sin coincidencias devuelve vacío', () {
      expect(findMatches('hola mundo', 'adios'), isEmpty);
    });
  });

  group('findMatches — las coincidencias no se solapan', () {
    test('«aa» sobre «aaa» da una sola coincidencia', () {
      // Dos rangos solapados se pintarían uno encima del otro en la burbuja.
      expect(findMatches('aaa', 'aa'), <MatchOffset>[const MatchOffset(0, 2)]);
    });

    test('«aa» sobre «aaaa» da dos coincidencias pegadas', () {
      expect(findMatches('aaaa', 'aa'), <MatchOffset>[
        const MatchOffset(0, 2),
        const MatchOffset(2, 4),
      ]);
    });
  });

  // ===============================================================================================
  // EL FIXTURE DORADO — lo que de verdad prueba que esto es un espejo
  // ===============================================================================================
  //
  // `message_search_golden.json` lo genera `tool/generate_search_golden.ts` ejecutando el
  // `_shared/text-search.ts` DE VERDAD sobre este corpus. Si alguien toca cualquiera de los dos
  // lados sin tocar el otro, este test se pone rojo — que es exactamente lo que un espejo necesita
  // y lo que ningún test escrito a mano puede garantizar.
  group('espejo de _shared/text-search.ts (fixture generado por Deno)', () {
    test('cada caso del corpus da los mismos offsets que el original en TypeScript', () {
      final File file = File('test/data/social/message_search_golden.json');
      expect(
        file.existsSync(),
        isTrue,
        reason:
            'Falta el fixture dorado. Se regenera con:\n'
            '  cd apps/backend/supabase/functions && deno run --allow-read '
            '../../../../mobile/tool/generate_search_golden.ts',
      );

      final List<dynamic> cases =
          jsonDecode(file.readAsStringSync()) as List<dynamic>;
      expect(cases, isNotEmpty);

      for (final dynamic raw in cases) {
        final Map<String, dynamic> c = raw as Map<String, dynamic>;
        final String haystack = c['haystack'] as String;
        final String needle = c['needle'] as String;
        final List<MatchOffset> expected =
            (c['matches'] as List<dynamic>)
                .map(
                  (dynamic m) => MatchOffset(
                    (m as Map<String, dynamic>)['start'] as int,
                    m['end'] as int,
                  ),
                )
                .toList();

        expect(
          findMatches(haystack, needle),
          expected,
          reason:
              'Divergencia con text-search.ts para '
              'haystack=${jsonEncode(haystack)} needle=${jsonEncode(needle)}',
        );
      }
    });
  });
}
