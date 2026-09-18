/// Espejo Dart de `_shared/text-search.ts` (§9.4) — resaltado dentro de la burbuja.
///
/// ## Por qué existe un espejo, si el backend ya devuelve los offsets
///
/// `messaging-search` calcula las coincidencias y las manda con sus offsets, y ésos son los
/// autoritativos. Este fichero cubre lo que no pasa por esa llamada: resaltar un mensaje que llega
/// por `stream()` mientras la búsqueda está abierta, o volver a resaltar sin ir al servidor. El
/// riesgo es exactamente el que `text-search.ts` documenta arriba del todo:
///
/// > *dos normalizaciones distintas a cada lado desplazan el resaltado*
///
/// Por eso esto no es "una búsqueda parecida": tiene que dar **los mismos offsets** que el
/// original. Lo prueba `test/data/social/message_search_test.dart` contra un fixture generado
/// ejecutando el `text-search.ts` de verdad en Deno (`tool/generate_search_golden.ts`).
///
/// ## La decisión que gobierna el fichero, heredada del original
///
/// **Los offsets son del texto ORIGINAL, no del normalizado**, y en unidades UTF-16 (que es como
/// indexan `String.indexOf`, `String.substring` y `TextSpan`). Normalizar puede **acortar** la
/// cadena —un texto descompuesto pierde sus acentos combinantes—, así que un offset del normalizado
/// señala el sitio equivocado y se desvía más cuantos más acentos haya antes. Se normaliza carácter
/// a carácter llevando un mapa de vuelta al original.
///
/// ## Lo que Dart no tiene, y cómo se suple
///
/// `text-search.ts` usa `String.normalize("NFD")`, que **no existe en `dart:core`** ni en Flutter.
/// Se sustituye por dos mecanismos que juntos dan el mismo resultado sobre el alfabeto latino:
///
///   1. **Descomponer**: una tabla de precompuestos → base ([_precomposedToBase]), que es lo que
///      NFD haría con «ó» (U+00F3) antes de que el `replace` le quitara el combinante.
///   2. **Quitar combinantes**: todo lo que caiga en U+0300–U+036F desaparece, igual que el
///      `replace` del original. Esto cubre el texto que **ya llega descompuesto**, venga del
///      alfabeto que venga.
///
/// **Frontera conocida y probada:** la tabla cubre Latin-1 Supplement (U+00C0–U+00FF) y Latin
/// Extended-A (U+0100–U+017F) — español, catalán, gallego, euskera, portugués, francés, alemán,
/// polaco, checo… Un precompuesto de fuera de esos bloques (vietnamita en U+1E00–U+1EFF, griego
/// o cirílico acentuado) **no se descompone**, igual que aquí no se descompone lo que NFD tampoco
/// toca (la «ß», que no tiene descomposición canónica: el fixture lo fija con
/// `Straße`/`strasse` → sin coincidencia, en los dos lados). Si algún día la app se traduce a una
/// de esas lenguas, hay que ampliar la tabla **y regenerar el fixture**, que es quien avisa.
library;

import 'package:flutter/foundation.dart';

/// Rango en unidades UTF-16 del texto **original**: `[start, end)`, como `String.substring`.
@immutable
class MatchOffset {
  const MatchOffset(this.start, this.end);

  final int start;
  final int end;

  @override
  bool operator ==(Object other) =>
      other is MatchOffset && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'MatchOffset($start, $end)';
}

/// Primer y último punto de código del bloque de diacríticos combinantes (`U+0300`–`U+036F`), el
/// mismo rango que el `replace` de `stripDiacritics` en `validation.ts`.
const int _combiningFirst = 0x0300;
const int _combiningLast = 0x036F;

/// Precompuestos latinos → su letra base, que es lo que NFD deja tras quitar el combinante.
///
/// Se escribe como dos cadenas alineadas y no como un `Map` literal porque así **se ve de un
/// vistazo que cada entrada tiene su pareja**: un `Map` de 180 líneas esconde un desalineamiento.
/// Un `assert` en [_buildDecompositionTable] comprueba las longitudes.
///
/// Las que NFD **no** descompone no están aquí, y es deliberado: `ß` (U+00DF), `æ`/`Æ`, `ø`/`Ø`,
/// `đ`/`Đ`, `ħ`/`Ħ`, `ı` (U+0131), `ŋ`/`Ŋ`, `œ`/`Œ`, `ŧ`/`Ŧ`. Añadirlas haría que el espejo
/// encontrase cosas que el original no encuentra, que es la divergencia que este fichero existe
/// para impedir.
const String _precomposed =
    // Latin-1 Supplement (U+00C0–U+00FF), sin Æ Ø × æ ø ÷ ß.
    'ÀÁÂÃÄÅÇÈÉÊË'
    'ÌÍÎÏÑÒÓÔÕÖ'
    'ÙÚÛÜÝ'
    'àáâãäåçèéêë'
    'ìíîïñòóôõö'
    'ùúûüýÿ'
    // Latin Extended-A (U+0100–U+017F), sin Đ đ Ħ ħ ı Ŋ ŋ Œ œ Ŧ ŧ y sin las ligaduras IJ/ij.
    'ĀāĂăĄąĆćĈĉĊċ'
    'ČčĎďĒēĔĕĖėĘę'
    'ĚěĜĝĞğĠġĢģĤĥ'
    'ĨĩĪīĬĭĮįİ'
    'ĴĵĶķĹĺĻļĽľ'
    'ŃńŅņŇň'
    'ŌōŎŏŐőŔŕŖŗŘř'
    'ŚśŜŝŞşŠšŢţŤť'
    'ŨũŪūŬŭŮůŰűŲų'
    'ŴŵŶŷŸŹźŻżŽž';

const String _bases =
    // Latin-1 Supplement.
    'AAAAAACEEEE'
    'IIIINOOOOO'
    'UUUUY'
    'aaaaaaceeee'
    'iiiinooooo'
    'uuuuyy'
    // Latin Extended-A.
    'AaAaAaCcCcCc'
    'CcDdEeEeEeEe'
    'EeGgGgGgGgHh'
    'IiIiIiIiI'
    'JjKkLlLlLl'
    'NnNnNn'
    'OoOoOoRrRrRr'
    'SsSsSsSsTtTt'
    'UuUuUuUuUuUu'
    'WwYyYZzZzZz';

Map<int, String> _buildDecompositionTable() {
  assert(
    _precomposed.length == _bases.length,
    'Las dos tablas de _precomposed/_bases están desalineadas: '
    '${_precomposed.length} precompuestos contra ${_bases.length} bases. '
    'Cada precompuesto tiene que tener su base en la MISMA posición.',
  );
  final Map<int, String> table = <int, String>{};
  for (int i = 0; i < _precomposed.length; i++) {
    table[_precomposed.codeUnitAt(i)] = _bases[i];
  }
  return table;
}

final Map<int, String> _decomposition = _buildDecompositionTable();

/// Insensible a mayúsculas y a diacríticos, que es lo que pide §9.4.
///
/// Espejo de `normalizeForSearch` en `text-search.ts`.
String normalizeForSearch(String value) {
  final StringBuffer out = StringBuffer();
  for (final int rune in value.runes) {
    if (rune >= _combiningFirst && rune <= _combiningLast) continue;
    final String? base = _decomposition[rune];
    out.write(base ?? String.fromCharCode(rune));
  }
  return out.toString().toLowerCase();
}

/// El texto normalizado, más el mapa que lleva cada unidad UTF-16 de vuelta al original.
class _NormalizedText {
  _NormalizedText(this.text, this.starts, this.ends, this.vanished);

  final String text;

  /// Por cada unidad UTF-16 de [text], dónde empieza su carácter en el original.
  final List<int> starts;

  /// Por cada unidad UTF-16 de [text], dónde acaba su carácter en el original.
  final List<int> ends;

  /// Caracteres del original que normalizan a **nada** (los combinantes), indexados por dónde
  /// empiezan. Sirven para que una coincidencia se trague el acento que le sigue.
  final Map<int, int> vanished;
}

/// Normaliza llevando la cuenta de dónde estaba cada cosa.
///
/// Se recorre por **puntos de código** (`runes`) pero el mapa se indexa por **unidades UTF-16**,
/// que es como indexa `indexOf` y `substring`. Mezclar las dos unidades es el fallo clásico aquí:
/// todo cuadra hasta que aparece un emoji, que ocupa dos unidades y un solo punto de código.
_NormalizedText _normalizeWithMap(String value) {
  final StringBuffer text = StringBuffer();
  final List<int> starts = <int>[];
  final List<int> ends = <int>[];
  final Map<int, int> vanished = <int, int>{};

  int at = 0;
  for (final int rune in value.runes) {
    // Unidades UTF-16 que ocupa este punto de código: 2 por encima del BMP.
    final int width = rune > 0xFFFF ? 2 : 1;
    final int from = at;
    final int to = at + width;

    final String normalized = rune >= _combiningFirst && rune <= _combiningLast
        ? ''
        : (_decomposition[rune] ?? String.fromCharCode(rune)).toLowerCase();

    if (normalized.isEmpty) {
      vanished[from] = to;
    } else {
      for (int k = 0; k < normalized.length; k++) {
        text.write(normalized[k]);
        starts.add(from);
        ends.add(to);
      }
    }

    at = to;
  }

  return _NormalizedText(text.toString(), starts, ends, vanished);
}

/// Todas las coincidencias de [needle] en [haystack], con sus offsets en el texto **original**.
///
/// No se solapan: el cliente resalta rangos, y dos rangos solapados se pintarían uno encima del
/// otro dentro de la burbuja. Espejo de `findMatches` en `text-search.ts`.
List<MatchOffset> findMatches(String haystack, String needle) {
  final String target = normalizeForSearch(needle).trim();

  // Sin esto, `indexOf('')` devuelve la posición de partida SIEMPRE y el bucle no termina nunca.
  // Pasa con una búsqueda de solo espacios o de un acento suelto, que normaliza a nada.
  if (target.isEmpty || haystack.isEmpty) return const <MatchOffset>[];

  final _NormalizedText normalized = _normalizeWithMap(haystack);
  final String text = normalized.text;
  final List<MatchOffset> matches = <MatchOffset>[];

  int from = 0;
  while (from <= text.length - target.length) {
    final int found = text.indexOf(target, from);
    if (found == -1) break;

    final int start = normalized.starts[found];
    int end = normalized.ends[found + target.length - 1];

    // El acento que sigue a la última letra se traga. «café» descompuesto es c-a-f-e-´: el final
    // "natural" caería en la `e` y dejaría la tilde fuera del resaltado, así que se pintaría
    // «cafe» resaltado y una tilde suelta sin resaltar justo encima. El bucle cubre los
    // combinantes apilados (varios diacríticos sobre la misma letra).
    int? next = normalized.vanished[end];
    while (next != null) {
      end = next;
      next = normalized.vanished[end];
    }

    matches.add(MatchOffset(start, end));
    from = found + target.length;
  }

  return matches;
}
