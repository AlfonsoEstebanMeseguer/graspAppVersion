import {
  assert,
  assertAlmostEquals,
  assertEquals,
} from "https://deno.land/std@0.208.0/assert/mod.ts";
import {
  type ConnectAxes,
  type ConnectCandidate,
  type ConnectFilter,
  type RandomSource,
  scoreCandidate,
  selectConnectBatch,
  weightedSampleWithoutReplacement,
} from "./connect-scoring.ts";
import type { ConnectExclusionSets } from "./connect-exclusions.ts";

function axes(over: Partial<ConnectAxes> = {}): ConnectAxes {
  return { ageYears: 30, interests: [], suffered: [], current: [], ...over };
}

/** N etiquetas distintas, para construir coincidencias contadas. */
function tags(prefix: string, n: number): string[] {
  return Array.from({ length: n }, (_, i) => `${prefix}-${i}`);
}

function filters(...active: ConnectFilter[]): ReadonlySet<ConnectFilter> {
  return new Set(active);
}

/** El chip `Todos` (RN-35): ningún filtro activo. */
const TODOS = filters();

// =================================================================================================
// §7.1 — la fórmula. Un test por fila de la tabla.
// =================================================================================================

Deno.test("§7.1 sin ninguna coincidencia todos los multiplicadores valen 1 y el score es 1", () => {
  // RN-41 vive o muere aquí: todo el mundo es ELEGIBLE. Un score de 0 sacaría a esta persona del
  // muestreo para siempre, que es exactamente lo que RN-41 prohíbe, y además rompería el reparto
  // de probabilidad (un peso 0 nunca se elige mientras quede otro).
  const b = scoreCandidate(axes({ ageYears: 20 }), axes({ ageYears: 60 }), TODOS);
  assertEquals(b, { age: 1, interests: 1, suffered: 1, current: 1, score: 1 });
});

Deno.test("§7.1 M_edad: los tres tramos y el resto, en sus bordes exactos", () => {
  // Los bordes son lo que importa: el `≤` de la tabla es inclusivo, y un `<` dejaría a los de
  // exactamente 2, 5 y 10 años de diferencia cayendo al tramo de abajo.
  const casos: Array<[number, number]> = [
    [0, 3.0],
    [2, 3.0], // borde inclusivo
    [3, 2.0],
    [5, 2.0], // borde inclusivo
    [6, 1.3],
    [10, 1.3], // borde inclusivo
    [11, 1.0], // «resto»
    [40, 1.0],
  ];
  for (const [diferencia, esperado] of casos) {
    const b = scoreCandidate(axes({ ageYears: 30 }), axes({ ageYears: 30 + diferencia }), TODOS);
    assertEquals(b.age, esperado, `diferencia de ${diferencia} anos`);
  }
});

Deno.test("§7.1 M_edad es simetrico: da igual quien sea mayor", () => {
  const mayor = scoreCandidate(axes({ ageYears: 40 }), axes({ ageYears: 30 }), TODOS);
  const menor = scoreCandidate(axes({ ageYears: 30 }), axes({ ageYears: 40 }), TODOS);
  assertEquals(mayor.age, menor.age);
});

Deno.test("§7.1 una edad ausente pondera neutro, NO excluye", () => {
  // La edad puede faltar (`birth_date` vive en `profiles_private` y no es obligatoria en todo
  // camino de alta). Ponderar 0 sería excluir por un dato ausente, y RN-41 lo prohíbe.
  for (const [a, b] of [[null, 30], [30, null], [null, null]] as Array<[number | null, number | null]>) {
    const r = scoreCandidate(axes({ ageYears: a }), axes({ ageYears: b }), TODOS);
    assertEquals(r.age, 1.0);
    assert(r.score > 0, "el score nunca puede ser 0");
  }
});

Deno.test("§7.1 los tres ejes de coincidencia usan su paso propio", () => {
  const comunes = tags("x", 2);
  const b = scoreCandidate(
    axes({ ageYears: null, interests: comunes, suffered: comunes, current: comunes }),
    axes({ ageYears: null, interests: comunes, suffered: comunes, current: comunes }),
    TODOS,
  );
  assertAlmostEquals(b.interests, 1 + 0.5 * 2); // 2.0
  assertAlmostEquals(b.suffered, 1 + 0.8 * 2); // 2.6
  assertAlmostEquals(b.current, 1 + 1.0 * 2); // 3.0
});

Deno.test("§7.1 los topes se aplican: 6 intereses comunes siguen siendo 3.0", () => {
  // 1 + 0.5 x 6 = 4.0, por encima del tope de 3.0. Sin tope, un perfil con muchas etiquetas
  // acapararia el muestreo entero.
  const seis = tags("i", 6);
  const b = scoreCandidate(
    axes({ ageYears: null, interests: seis, suffered: seis, current: seis }),
    axes({ ageYears: null, interests: seis, suffered: seis, current: seis }),
    TODOS,
  );
  assertEquals(b.interests, 3.0); // tope de intereses
  assertEquals(b.suffered, 3.0); // 1 + 0.8 x 6 = 5.8 -> 3.0
  assertEquals(b.current, 3.5); // 1 + 1.0 x 6 = 7.0 -> 3.5
});

Deno.test("§7.1 solo cuentan las coincidencias, y una repetida cuenta una vez", () => {
  // Si contara ocurrencias en vez de valores distintos, cualquiera podria inflar su propio score
  // repitiendo una etiqueta. El scoring es servidor, pero el dato de origen lo escribe el usuario.
  const b = scoreCandidate(
    axes({ ageYears: null, interests: ["a", "a", "a", "b"] }),
    axes({ ageYears: null, interests: ["a", "a", "b", "c"] }),
    TODOS,
  );
  assertAlmostEquals(b.interests, 1 + 0.5 * 2); // {a, b} en comun: dos, no cinco
});

// =================================================================================================
// §7.2 — el efecto del filtro (RN-42).
// =================================================================================================

/** El caso del §7.2, con un multiplicador distinto en cada eje para que se vea cuál se movió. */
function conCuatroEjesDistintos(active: ReadonlySet<ConnectFilter>) {
  return scoreCandidate(
    axes({ ageYears: 30, interests: tags("i", 2), suffered: tags("s", 1), current: tags("c", 1) }),
    axes({ ageYears: 31, interests: tags("i", 2), suffered: tags("s", 1), current: tags("c", 1) }),
    active,
  );
}

Deno.test("RN-35 `Todos` no eleva ningun multiplicador", () => {
  const b = conCuatroEjesDistintos(TODOS);
  assertEquals(b.age, 3.0);
  assertAlmostEquals(b.interests, 2.0);
  assertAlmostEquals(b.suffered, 1.8);
  assertAlmostEquals(b.current, 2.0);
  assertAlmostEquals(b.score, 3.0 * 2.0 * 1.8 * 2.0);
});

Deno.test("RN-42 el filtro Edad eleva SU multiplicador al cuadrado y deja los demas intactos", () => {
  // El ejemplo literal del §7.2: score = M_edad^2 x M_intereses x M_sufrida x M_actual.
  const sin = conCuatroEjesDistintos(TODOS);
  const con = conCuatroEjesDistintos(filters("age"));

  assertEquals(con.age, 3.0 * 3.0); // el suyo, al cuadrado
  assertEquals(con.interests, sin.interests); // los demas, intactos
  assertEquals(con.suffered, sin.suffered);
  assertEquals(con.current, sin.current);
  assertAlmostEquals(con.score, 9.0 * 2.0 * 1.8 * 2.0);
});

Deno.test("RN-42 cada uno de los cuatro filtros eleva el suyo y solo el suyo", () => {
  // Un test por eje se olvida del eje que se anada manana; este recorre el mapa entero.
  const sin = conCuatroEjesDistintos(TODOS);
  const ejes: ConnectFilter[] = ["age", "interests", "suffered", "current"];

  for (const eje of ejes) {
    const con = conCuatroEjesDistintos(filters(eje));
    for (const otro of ejes) {
      if (otro === eje) {
        assertAlmostEquals(con[eje], sin[eje] * sin[eje], 1e-9, `${eje} deberia ir al cuadrado`);
      } else {
        assertEquals(con[otro], sin[otro], `${otro} no deberia moverse con el filtro ${eje}`);
      }
    }
  }
});

Deno.test("RN-34 varios filtros a la vez elevan varios multiplicadores", () => {
  const sin = conCuatroEjesDistintos(TODOS);
  const con = conCuatroEjesDistintos(filters("age", "current"));

  assertEquals(con.age, sin.age * sin.age);
  assertAlmostEquals(con.current, sin.current * sin.current);
  assertEquals(con.interests, sin.interests); // sin filtro: intacto
  assertEquals(con.suffered, sin.suffered);
  assertAlmostEquals(con.score, 9.0 * 2.0 * 1.8 * 4.0);
});

Deno.test("RN-41 el filtro no excluye a nadie: con filtro el score sigue siendo > 0", () => {
  // «Con el filtro Edad activo puede seguir apareciendo alguien de edad muy distinta». Si el filtro
  // excluyera, este score seria 0 y el muestreo no la elegiria jamas.
  const b = scoreCandidate(axes({ ageYears: 20 }), axes({ ageYears: 70 }), filters("age"));
  assertEquals(b.age, 1.0); // fuera de todo tramo, pero 1 al cuadrado sigue siendo 1
  assertEquals(b.score, 1);
});

// =================================================================================================
// §7.3 — muestreo aleatorio ponderado SIN REPOSICIÓN (RN-44).
// =================================================================================================

/** Generador determinista: el test no puede depender de `Math.random` o no significa nada. */
function secuencia(...valores: number[]): RandomSource {
  let i = 0;
  return () => valores[i++ % valores.length];
}

/** LCG con semilla, para los tests de distribución. Determinista y reproducible. */
function lcg(semilla: number): RandomSource {
  let s = semilla >>> 0;
  return () => {
    s = (Math.imul(s, 1664525) + 1013904223) >>> 0;
    return s / 0x100000000;
  };
}

const PESADO = { userId: "pesado", peso: 10 };
const LIGERO = { userId: "ligero", peso: 1 };
const peso = (x: { peso: number }) => x.peso;

Deno.test("RN-44 es muestreo, NO ordenacion por score: el ligero puede salir primero", () => {
  // ESTE ES EL TEST QUE DISTINGUE LAS DOS IMPLEMENTACIONES. Una ordenacion por score pasaria
  // todos los demas tests de este bloque y fallaria este, que es justo lo que RN-44 prohibe:
  // «muestreo aleatorio ponderado, NO ordenacion determinista por score».
  const r = weightedSampleWithoutReplacement([PESADO, LIGERO], peso, 2, secuencia(0.99));
  assertEquals(r[0].userId, "ligero");
});

Deno.test("RN-44 el peso alto sube la probabilidad: con el sorteo bajo sale el pesado", () => {
  const r = weightedSampleWithoutReplacement([PESADO, LIGERO], peso, 2, secuencia(0.0));
  assertEquals(r[0].userId, "pesado");
});

Deno.test("RN-44 sin reposicion: nadie sale dos veces en la misma tanda", () => {
  const pool = Array.from({ length: 12 }, (_, i) => ({ userId: `u${i}`, peso: i + 1 }));
  const r = weightedSampleWithoutReplacement(pool, peso, 12, lcg(7));
  assertEquals(r.length, 12);
  assertEquals(new Set(r.map((x) => x.userId)).size, 12, "hay repetidos");
});

Deno.test("RN-44 un score alto sube la probabilidad sin garantizar el primer puesto", () => {
  // La mitad que ningun caso concreto puede probar: que el peso SESGA. 9 a 1 deberia salir
  // primero en torno al 90% de las veces, y el resto de las veces NO.
  const pool = [{ userId: "a", peso: 9 }, { userId: "b", peso: 1 }];
  const random = lcg(20260825);
  let primeroA = 0;
  const TIRADAS = 4000;
  for (let i = 0; i < TIRADAS; i++) {
    if (weightedSampleWithoutReplacement(pool, peso, 1, random)[0].userId === "a") primeroA++;
  }
  const ratio = primeroA / TIRADAS;
  assert(ratio > 0.85 && ratio < 0.95, `sesgo fuera de rango: ${ratio}`);
  assert(primeroA < TIRADAS, "el peso alto NO puede garantizar el primer puesto");
});

Deno.test("RN-44 pedir mas de los que hay devuelve a todos, sin huecos ni undefined", () => {
  const pool = [PESADO, LIGERO];
  const r = weightedSampleWithoutReplacement(pool, peso, 20, secuencia(0.5));
  assertEquals(r.length, 2);
  assertEquals(new Set(r.map((x) => x.userId)), new Set(["pesado", "ligero"]));
});

Deno.test("RN-44 casos degenerados no devuelven undefined", () => {
  assertEquals(weightedSampleWithoutReplacement([], peso, 5, secuencia(0.5)), []);
  assertEquals(weightedSampleWithoutReplacement([PESADO], peso, 0, secuencia(0.5)), []);
  // Un sorteo que devuelve exactamente 1.0 no puede caerse del ultimo tramo por redondeo.
  const r = weightedSampleWithoutReplacement([PESADO, LIGERO], peso, 2, secuencia(1.0));
  assertEquals(r.length, 2);
  assert(r.every((x) => x !== undefined));
});

// =================================================================================================
// §7.3 + §7.4 — la tanda completa: exclusiones, relajación (RN-49) y muestreo.
// =================================================================================================

function candidato(id: string, over: Partial<ConnectAxes> = {}): ConnectCandidate {
  return { userId: id, ...axes(over) };
}

function sets(over: Partial<ConnectExclusionSets> = {}): ConnectExclusionSets {
  return {
    viewerId: "yo",
    blockedByViewer: new Set(),
    blockedTheViewer: new Set(),
    conversations: new Set(),
    pendingRequestsSent: new Set(),
    pendingRequestsReceived: new Set(),
    following: new Set(),
    dismissed: new Set(),
    shownToday: new Set(),
    ...over,
  };
}

Deno.test("RN-46 la tanda se corta en BATCH_SIZE cuando hay de sobra", () => {
  const pool = Array.from({ length: 50 }, (_, i) => candidato(`u${i}`));
  const r = selectConnectBatch(axes(), pool, sets(), TODOS, lcg(1));
  assertEquals(r.kind, "batch");
  assertEquals(r.candidates.length, 20);
  assertEquals(new Set(r.candidates.map((c) => c.userId)).size, 20);
});

Deno.test("RN-49 con pocos elegibles se relaja el filtro, y se dice que se relajo", () => {
  const pool = Array.from({ length: 3 }, (_, i) => candidato(`u${i}`));
  const r = selectConnectBatch(axes(), pool, sets(), filters("age"), lcg(1));
  assertEquals(r.kind, "relaxed");
  assertEquals(r.candidates.length, 3);
});

Deno.test("RN-49 relajado puntua SIN el cuadrado del filtro", () => {
  // Es lo unico que la relajacion puede cambiar de verdad: como RN-41 hace del filtro un peso
  // puro, relajarlo no anade ni un candidato — solo deja de concentrar la probabilidad.
  const joven = candidato("joven", { ageYears: 30 });
  const lejano = candidato("lejano", { ageYears: 70 });
  const pool = [joven, lejano];

  // EL VALOR DEL SORTEO ESTA ELEGIDO PARA QUE DISCRIMINE, que es lo unico que hace util a este
  // test. Con 0.5 las dos implementaciones dan el mismo resultado y el test seria vacuo:
  //   · relajado (3 a 1): total 4, r = 3.2 -> el joven acumula 3.0, no llega: sale el LEJANO.
  //   · con el cuadrado (9 a 1): total 10, r = 8.0 -> el joven acumula 9.0 y se lo lleva.
  // Solo un r en [0.75, 0.9) separa las dos. Si alguien vuelve a aplicar el filtro aqui, cae.
  const relajado = selectConnectBatch(axes({ ageYears: 30 }), pool, sets(), filters("age"), secuencia(0.8));
  assertEquals(relajado.kind, "relaxed");
  assertEquals(relajado.candidates[0].userId, "lejano");
});

Deno.test("RN-49 sin ningun elegible se devuelve empty, no una lista vacia sin explicacion", () => {
  const pool = [candidato("a"), candidato("b")];
  const r = selectConnectBatch(
    axes(),
    pool,
    sets({ dismissed: new Set(["a", "b"]) }),
    TODOS,
    lcg(1),
  );
  assertEquals(r.kind, "empty");
  assertEquals(r.candidates, []);
});

Deno.test("RN-49 RELAJAR EL FILTRO NO RELAJA LAS EXCLUSIONES", () => {
  // El atajo que un implementador tiene a mano —«no hay bastantes, tiro del pool completo»— y que
  // rompe RN-24: un bloqueado reaparece en Conectar justo cuando escasean los candidatos.
  const pool = Array.from({ length: 25 }, (_, i) => candidato(`u${i}`));
  const prohibidos = new Set(pool.slice(3).map((c) => c.userId)); // 22 fuera, 3 elegibles

  const r = selectConnectBatch(
    axes(),
    pool,
    sets({ blockedTheViewer: prohibidos }),
    filters("age"),
    lcg(3),
  );

  assertEquals(r.kind, "relaxed");
  assertEquals(r.candidates.length, 3);
  for (const c of r.candidates) {
    assert(!prohibidos.has(c.userId), `${c.userId} esta excluido y ha salido igualmente`);
  }
});

Deno.test("RN-47 la tanda nunca incluye al propio espectador", () => {
  const pool = [candidato("yo"), candidato("otro")];
  const r = selectConnectBatch(axes(), pool, sets(), TODOS, lcg(1));
  assertEquals(r.candidates.map((c) => c.userId), ["otro"]);
});
