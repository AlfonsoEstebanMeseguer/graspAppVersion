import { assertEquals } from "https://deno.land/std@0.208.0/assert/mod.ts";
import { isValidTag, normalizeTagLocalPart } from "./tag.ts";

// ---------------------------------------------------------------------------------------------
// normalizeTagLocalPart — espejo de la mitad local de `public.mint_user_tag`.
// Los cuatro primeros casos son LITERALMENTE los del plan de la Fase 4, verificados contra la
// base local el 2026-08-23. Si uno de ellos cambia, o cambia el SQL o cambia este fichero, pero
// nunca uno solo de los dos.
// ---------------------------------------------------------------------------------------------

Deno.test("normalizeTagLocalPart: 'Alfonso Esteban' con tilde pierde la tilde y se trunca a 12", () => {
  assertEquals(normalizeTagLocalPart("Alfonso Estebán"), "alfonsoesteb");
});

Deno.test("normalizeTagLocalPart: 'Maria Jose' con tilde cabe entera", () => {
  assertEquals(normalizeTagLocalPart("María José"), "mariajose");
});

Deno.test("normalizeTagLocalPart: un nombre entero en cirilico cae al fallback", () => {
  assertEquals(normalizeTagLocalPart("Дмитрий"), "grasp");
});

Deno.test("normalizeTagLocalPart: solo espacios cae al fallback", () => {
  assertEquals(normalizeTagLocalPart("   "), "grasp");
});

Deno.test("normalizeTagLocalPart: cadena vacia cae al fallback", () => {
  assertEquals(normalizeTagLocalPart(""), "grasp");
});

Deno.test("normalizeTagLocalPart: un nombre entero en emoji cae al fallback", () => {
  assertEquals(normalizeTagLocalPart("🌈🌈🌈"), "grasp");
});

Deno.test("normalizeTagLocalPart: los digitos se conservan", () => {
  assertEquals(normalizeTagLocalPart("Ana 99"), "ana99");
});

Deno.test("normalizeTagLocalPart: exactamente 12 caracteres no se trunca", () => {
  assertEquals(normalizeTagLocalPart("abcdefghijkl"), "abcdefghijkl");
});

Deno.test("normalizeTagLocalPart: 13 caracteres se truncan a 12", () => {
  assertEquals(normalizeTagLocalPart("abcdefghijklm"), "abcdefghijkl");
});

Deno.test("normalizeTagLocalPart: la puntuacion interna desaparece, no separa", () => {
  // A diferencia de `toSlug`, que mete un '-'. El tag no admite guiones: se teclea a mano.
  assertEquals(normalizeTagLocalPart("Ana-Maria O'Neill"), "anamariaonei");
});

Deno.test("normalizeTagLocalPart: NFC y NFD del mismo nombre dan el mismo resultado", () => {
  // El nombre llega como lo mande el cliente. Si estas dos divergieran, dos usuarios con el
  // "mismo" nombre acunarian partes locales distintas segun como su teclado componga la tilde.
  const nfc = "José".normalize("NFC");
  const nfd = "José".normalize("NFD");
  assertEquals(normalizeTagLocalPart(nfc), normalizeTagLocalPart(nfd));
  assertEquals(normalizeTagLocalPart(nfc), "jose");
});

Deno.test("normalizeTagLocalPart: la enie se reduce a 'n', no al fallback", () => {
  assertEquals(normalizeTagLocalPart("Begoña"), "begona");
});

// ---------------------------------------------------------------------------------------------
// isValidTag — espejo del formato acunado por `public.mint_user_tag`.
// El alfabeto es Crockford base32: SIN I, L, O ni U. Los cuatro tests de esas letras son el
// motivo entero de haber elegido ese alfabeto (el tag se teclea a mano en un movil), asi que
// van uno por letra y no agrupados.
// ---------------------------------------------------------------------------------------------

Deno.test("isValidTag: el tag del ejemplo de la spec es valido", () => {
  assertEquals(isValidTag("alfon#K7M2QX9F"), true);
});

Deno.test("isValidTag: parte local de un solo caracter es valida", () => {
  assertEquals(isValidTag("a#01234567"), true);
});

Deno.test("isValidTag: parte local de 12 caracteres es valida", () => {
  assertEquals(isValidTag("abcdefghijkl#0123456J"), true);
});

Deno.test("isValidTag: parte local de 13 caracteres no es valida", () => {
  assertEquals(isValidTag("abcdefghijklm#0123456J"), false);
});

Deno.test("isValidTag: parte local vacia no es valida", () => {
  assertEquals(isValidTag("#0123456J"), false);
});

Deno.test("isValidTag: parte local en mayusculas no es valida", () => {
  assertEquals(isValidTag("Alfon#K7M2QX9F"), false);
});

Deno.test("isValidTag: un guion en la parte local no es valido", () => {
  assertEquals(isValidTag("al-fon#K7M2QX9F"), false);
});

Deno.test("isValidTag: sufijo en minusculas no es valido", () => {
  assertEquals(isValidTag("alfon#k7m2qx9f"), false);
});

Deno.test("isValidTag: la letra I esta fuera del alfabeto Crockford", () => {
  assertEquals(isValidTag("alfon#K7M2QX9I"), false);
});

Deno.test("isValidTag: la letra L esta fuera del alfabeto Crockford", () => {
  assertEquals(isValidTag("alfon#K7M2QX9L"), false);
});

Deno.test("isValidTag: la letra O esta fuera del alfabeto Crockford", () => {
  assertEquals(isValidTag("alfon#K7M2QX9O"), false);
});

Deno.test("isValidTag: la letra U esta fuera del alfabeto Crockford", () => {
  assertEquals(isValidTag("alfon#K7M2QX9U"), false);
});

Deno.test("isValidTag: sufijo de 7 caracteres no es valido", () => {
  assertEquals(isValidTag("alfon#K7M2QX9"), false);
});

Deno.test("isValidTag: sufijo de 9 caracteres no es valido", () => {
  assertEquals(isValidTag("alfon#K7M2QX9FA"), false);
});

Deno.test("isValidTag: sin almohadilla no es valido", () => {
  assertEquals(isValidTag("alfonK7M2QX9F"), false);
});

Deno.test("isValidTag: dos almohadillas no es valido", () => {
  assertEquals(isValidTag("al#fon#K7M2QX9F"), false);
});

Deno.test("isValidTag: con espacios alrededor no es valido", () => {
  assertEquals(isValidTag(" alfon#K7M2QX9F "), false);
});

Deno.test("isValidTag: cadena vacia no es valida", () => {
  assertEquals(isValidTag(""), false);
});

Deno.test("isValidTag: un salto de linea al final no es valido", () => {
  // `$` en JavaScript acepta un '\n' final salvo que el patron use `\z`... que no existe. El
  // regex tiene que estar escrito de forma que esto NO pase.
  assertEquals(isValidTag("alfon#K7M2QX9F\n"), false);
});

Deno.test("isValidTag: un numero no es un tag", () => {
  assertEquals(isValidTag(42), false);
});

Deno.test("isValidTag: null no es un tag", () => {
  assertEquals(isValidTag(null), false);
});

// ---------------------------------------------------------------------------------------------
// Los dos juntos: lo que acuna la parte local siempre encaja en el formato que valida isValidTag.
// ---------------------------------------------------------------------------------------------

Deno.test("normalizeTagLocalPart + isValidTag: el fallback tambien forma un tag valido", () => {
  assertEquals(isValidTag(`${normalizeTagLocalPart("Дмитрий")}#K7M2QX9F`), true);
});

Deno.test("normalizeTagLocalPart + isValidTag: un nombre hostil forma un tag valido", () => {
  const local = normalizeTagLocalPart("  Ángel-Мария 🌈 O'Brien-Fitzgerald  ");
  assertEquals(isValidTag(`${local}#0123456J`), true);
});
