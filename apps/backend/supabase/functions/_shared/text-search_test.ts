import { assertEquals } from "https://deno.land/std@0.208.0/assert/mod.ts";
import { findMatches, normalizeForSearch } from "./text-search.ts";
import { toSlug } from "./validation.ts";

// NOTA DE MÉTODO, y es lo que hace que estos tests prueben algo:
//
// Ningún texto descompuesto se TECLEA — se construye con `.normalize("NFD")`. Un literal
// "canción" escrito en este fichero acaba precompuesto (una sola unidad para la ó), así que un test
// que pretendiera comparar "precompuesto contra descompuesto" con dos literales estaría comparando
// la cadena consigo misma y saldría verde sin probar nada. Es el mismo fallo que un fixture que
// vuelve vacuo un test de regresión.

// =================================================================================================
// normalizeForSearch — insensible a mayúsculas y a diacríticos (§9.4)
// =================================================================================================

Deno.test("§12: «Canción» y «cancion» normalizan a lo mismo, en los dos sentidos", () => {
  assertEquals(normalizeForSearch("Canción"), "cancion");
  assertEquals(normalizeForSearch("cancion"), "cancion");
  assertEquals(normalizeForSearch("CANCIÓN"), "cancion");
});

Deno.test("la eñe también pierde el diacrítico: «año» y «ano» se encuentran", () => {
  // Consecuencia deliberada de NFD: en una búsqueda insensible a acentos, la tilde de la eñe es un
  // diacrítico más. Se deja escrito porque sorprende en español.
  assertEquals(normalizeForSearch("año"), normalizeForSearch("ano"));
});

Deno.test("normaliza igual un texto precompuesto y el mismo texto descompuesto", () => {
  const precompuesto = "canción";
  const descompuesto = precompuesto.normalize("NFD");

  assertEquals(precompuesto.length, 7);
  assertEquals(descompuesto.length, 8);
  assertEquals(normalizeForSearch(precompuesto), normalizeForSearch(descompuesto));
});

Deno.test("no toca lo que no es diacrítico: emojis y signos sobreviven", () => {
  assertEquals(normalizeForSearch("¿Vamos? 🌈"), "¿vamos? 🌈");
});

// =================================================================================================
// findMatches — y sobre todo, DÓNDE caen los offsets
// =================================================================================================

Deno.test("§12: buscar sin acento encuentra el texto con acento", () => {
  const texto = "La canción favorita";
  const encontrado = findMatches(texto, "cancion");

  assertEquals(encontrado.length, 1);
  assertEquals(texto.slice(encontrado[0].start, encontrado[0].end), "canción");
});

Deno.test("§12: buscar CON acento encuentra el texto sin acento", () => {
  const texto = "La cancion favorita";
  const encontrado = findMatches(texto, "canción");

  assertEquals(encontrado.length, 1);
  assertEquals(texto.slice(encontrado[0].start, encontrado[0].end), "cancion");
});

Deno.test("es insensible a mayúsculas", () => {
  assertEquals(findMatches("Hola MUNDO", "mundo"), [{ start: 5, end: 10 }]);
});

Deno.test("devuelve TODAS las coincidencias, en orden", () => {
  const texto = "ana y ANA y aná";
  const encontrado = findMatches(texto, "ana");

  assertEquals(encontrado.length, 3);
  assertEquals(encontrado.map((m) => texto.slice(m.start, m.end)), ["ana", "ANA", "aná"]);
});

Deno.test("LOS OFFSETS SON DEL TEXTO ORIGINAL, no del normalizado", () => {
  // EL TEST QUE SOSTIENE EL MÓDULO. Con el texto ya descompuesto, normalizar ACORTA la cadena: 11
  // unidades pasan a 10. Una implementación que devolviera los offsets del texto normalizado
  // resaltaría un carácter de menos, y se desplazaría más cuantos más acentos hubiera antes.
  const texto = "canción ya".normalize("NFD");

  assertEquals(texto.length, 11);
  assertEquals(normalizeForSearch(texto).length, 10);

  const encontrado = findMatches(texto, "cancion");

  assertEquals(encontrado, [{ start: 0, end: 8 }]);
  assertEquals(texto.slice(0, 8), "canción".normalize("NFD"));
});

Deno.test("los offsets cuentan en unidades UTF-16, que es como indexa Dart", () => {
  // Un emoji ocupa DOS unidades. Contando puntos de código, el resaltado en Flutter saldría corrido
  // hacia la izquierda en cuanto hubiera un emoji antes de la coincidencia.
  const texto = "🌈 hola";

  assertEquals(texto.length, 7);
  assertEquals(findMatches(texto, "hola"), [{ start: 3, end: 7 }]);
});

Deno.test("una coincidencia que acaba en un acento descompuesto SE LO TRAGA", () => {
  // "café" descompuesto es c-a-f-e-´ (5 unidades). El acento normaliza a nada, así que el final
  // "natural" de la coincidencia caería en 4 y dejaría la tilde fuera del resaltado: el cliente
  // pintaría "cafe" resaltado y una tilde suelta sin resaltar, encima de la e.
  const texto = "café".normalize("NFD");

  assertEquals(texto.length, 5);
  assertEquals(findMatches(texto, "cafe"), [{ start: 0, end: 5 }]);
});

Deno.test("las coincidencias NO se solapan", () => {
  // "aaa" con "aa" da UNA, no dos: el cliente resalta rangos, y dos rangos solapados se pintarían
  // uno encima del otro.
  assertEquals(findMatches("aaa", "aa"), [{ start: 0, end: 2 }]);
});

Deno.test("sin coincidencias devuelve lista vacía", () => {
  assertEquals(findMatches("hola mundo", "adios"), []);
});

Deno.test("una búsqueda que normaliza a vacío no devuelve nada y no se cuelga", () => {
  // Buscar solo un acento suelto normaliza a "". Sin este guardia, `indexOf("")` devuelve la
  // posición de partida siempre y el bucle no termina nunca.
  const soloAcento = "́".normalize("NFD");

  assertEquals(normalizeForSearch(soloAcento), "");
  assertEquals(findMatches("hola", soloAcento), []);
  assertEquals(findMatches("hola", ""), []);
  assertEquals(findMatches("hola", "   "), []);
});

Deno.test("un texto vacío no casa con nada", () => {
  assertEquals(findMatches("", "hola"), []);
});

// =================================================================================================
// La factorización: `toSlug` sigue funcionando sobre el mismo primitivo
// =================================================================================================

Deno.test("`toSlug` conserva su comportamiento tras compartir el quitado de diacríticos", () => {
  assertEquals(toSlug("Ansiedad y Depresión"), "ansiedad-y-depresion");
  assertEquals(toSlug("  Trastorno  Bipolar  "), "trastorno-bipolar");
});
