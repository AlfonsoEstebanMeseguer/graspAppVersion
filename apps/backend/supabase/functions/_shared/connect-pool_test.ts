// La cobertura del pool de Conectar (ADR 0030).
//
// LO QUE ESTOS TESTS FIJAN es que el aviso llegue por sí solo cuando la muestra deje de cubrir la
// base. El número anterior —`MAX_POOL = 1000`— vivía en un comentario que decía «revisar cuando la
// base crezca», y eso depende de que alguien se acuerde: un mecanismo sin puerta de entrada.
import { assertEquals } from "jsr:@std/assert@1";
import {
  MAX_POOL,
  POOL_COVERAGE_MIN,
  poolCoverage,
  poolCoverageIsLow,
} from "./connect-pool.ts";

Deno.test("con la base mas pequena que la muestra, la cobertura es 1: el tope no existe", () => {
  assertEquals(poolCoverage(0), 1);
  assertEquals(poolCoverage(1), 1);
  assertEquals(poolCoverage(MAX_POOL), 1);
  // Y no avisa: no hay nada que avisar mientras la muestra ES la tabla entera.
  assertEquals(poolCoverageIsLow(MAX_POOL), false);
});

Deno.test("la cobertura es la fraccion de la base que cabe en una muestra", () => {
  assertEquals(poolCoverage(MAX_POOL * 2), 0.5);
  assertEquals(poolCoverage(MAX_POOL * 4), 0.25);
});

Deno.test("el umbral muerde justo donde el ADR 0030 dice, y el limite exacto NO avisa", () => {
  // `< POOL_COVERAGE_MIN`, no `<=`: con la cobertura exactamente en el umbral todavia se cubre lo
  // prometido. Una alerta que salta en el valor aceptable se deja de leer.
  assertEquals(poolCoverage(MAX_POOL * 2), POOL_COVERAGE_MIN);
  assertEquals(poolCoverageIsLow(MAX_POOL * 2), false);
  assertEquals(poolCoverageIsLow(MAX_POOL * 2 + 1), true);
});

Deno.test("un recuento negativo o absurdo no rompe ni avisa en falso", () => {
  // El hecho viene de un `count` de Postgres; si algun dia llega raro, el digest no debe empezar a
  // alertar todos los dias sobre un sistema sano.
  assertEquals(poolCoverage(-5), 1);
  assertEquals(poolCoverageIsLow(-5), false);
});

Deno.test("MAX_POOL vive en UN solo sitio y es el que usa connect-feed", async () => {
  // Si este numero se duplicara, el digest vigilaria un tope distinto del que aplica el feed y su
  // aviso seria una mentira tranquilizadora. Se comprueba que el handler lo IMPORTA en vez de
  // declararlo: buscar `const MAX_POOL` en su fuente debe dar cero.
  const source = await Deno.readTextFile(
    new URL("../connect-feed/index.ts", import.meta.url),
  );
  assertEquals(/const\s+MAX_POOL\s*=/.test(source), false);
  assertEquals(source.includes("connect-pool.ts"), true);
});
