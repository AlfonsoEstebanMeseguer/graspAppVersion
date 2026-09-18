// Genera `test/data/social/message_search_golden.json` ejecutando el `_shared/text-search.ts` DE
// VERDAD sobre un corpus. Es lo que convierte a `data/social/message_search.dart` en un espejo
// demostrado y no en una reimplementacion parecida: si cualquiera de los dos lados cambia sin el
// otro, el test de Flutter que lee este fichero se pone rojo.
//
// Se regenera desde `apps/mobile` con:
//
//   deno run --allow-write=test/data/social/message_search_golden.json \
//     tool/generate_search_golden.ts
//
// EL FICHERO ES ASCII PURO A PROPOSITO. Todo caracter acentuado va con `\uXXXX`, porque la
// distincion que este corpus existe para probar -compuesto (U+00F3) contra descompuesto
// (o + U+0301)- es invisible al leerla y cualquier editor que normalice el fichero la borraria
// sin que nadie se entere, dejando el fixture pasando pero sin cubrir nada.
//
// El corpus vive aqui y no en el JSON: el JSON es SALIDA, y editarlo a mano lo convertiria en un
// fixture que ya no prueba nada.
import { findMatches } from "../../backend/supabase/functions/_shared/text-search.ts";

/** `[pajar, aguja]`. */
const CORPUS: Array<[string, string]> = [
  // --- Lo que pide el plan: Cancion/cancion en los dos sentidos.
  ["Canci\u00F3n", "cancion"],
  ["cancion", "Canci\u00F3n"],
  ["Canci\u00F3n", "Canci\u00F3n"],

  // --- Mayusculas.
  ["HOLA hola HoLa", "hola"],
  ["Hola Mundo", "MUNDO"],

  // --- COMPUESTO (U+00F3) contra DESCOMPUESTO (o + U+0301). El nucleo del espejo.
  ["canci\u00F3n bonita", "bonita"],
  ["cancio\u0301n bonita", "bonita"],
  ["canci\u00F3n", "cancion"],
  ["cancio\u0301n", "cancion"],
  ["cancion", "canci\u00F3n"],
  ["cancion", "cancio\u0301n"],
  ["canci\u00F3n", "cancio\u0301n"],
  ["cancio\u0301n", "canci\u00F3n"],
  ["caf\u00E9", "cafe"],
  ["cafe\u0301", "cafe"],
  ["cafe", "caf\u00E9"],
  ["cafe", "cafe\u0301"],

  // --- Combinantes apilados sobre la misma letra.
  ["cafe\u0301\u0308", "cafe"],
  ["a\u0301\u0300\u0302bc", "abc"],

  // --- Vocales acentuadas del espanol, enye y dieresis.
  ["\u00C1\u00C9\u00CD\u00D3\u00DA\u00DC\u00D1 \u00E1\u00E9\u00ED\u00F3\u00FA\u00FC\u00F1", "aeiouun"],
  ["El ping\u00FCino so\u00F1\u00F3", "PINGUINO"],
  ["Ma\u00F1ana", "manana"],
  ["so\u00F1\u00F3", "sono"],

  // --- Pares suplentes: los offsets van en unidades UTF-16, no en puntos de codigo.
  ["\u{1F3B5}Canci\u00F3n", "cancion"],
  ["a\u{1F3B5}b\u{1F3B5}c", "b"],
  ["\u{1F3B5}\u{1F3B5}\u{1F3B5}fin", "fin"],
  ["Canci\u00F3n \u{1F3B5} alegre", "alegre"],
  ["cancio\u0301n \u{1F3B5} alegre", "alegre"],

  // --- Solapamiento: las coincidencias no se pisan.
  ["aaa", "aa"],
  ["aaaa", "aa"],
  ["ababab", "abab"],

  // --- Vacios y agujas que normalizan a nada (las que cuelgan el bucle si se hacen mal).
  ["lo que sea", ""],
  ["lo que sea", "   "],
  ["lo que sea", "\u0301"],
  ["", "hola"],
  ["", ""],
  ["hola mundo", "adios"],

  // --- La aguja se recorta.
  ["hola mundo", "  mundo  "],

  // --- Otras lenguas latinas: hasta donde llega el espejo.
  ["\u00C6r\u00F8sk\u00F8bing", "aeroskobing"],
  ["\u0141\u00F3d\u017A", "lodz"],
  ["\u010De\u0161tina", "cestina"],
  ["\u00C7a va", "ca va"],
  ["Stra\u00DFe", "strasse"],

  // --- Textos largos con varias coincidencias y acentos por medio.
  ["La canci\u00F3n son\u00F3, y otra cancio\u0301n mas tarde son\u00F3", "cancion"],
  ["a\u0301 \u00E1 a\u0301", "a"],

];

const cases = CORPUS.map(([haystack, needle]) => ({
  haystack,
  needle,
  matches: findMatches(haystack, needle),
}));

const target = new URL(
  "../test/data/social/message_search_golden.json",
  import.meta.url,
);
await Deno.writeTextFile(target, `${JSON.stringify(cases, null, 2)}\n`);
console.log(`Escritos ${cases.length} casos en ${target.pathname}`);
