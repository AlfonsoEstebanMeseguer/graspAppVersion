import { assertEquals } from "https://deno.land/std@0.208.0/assert/mod.ts";
import {
  decideReconcile,
  evaluateBrake,
  extractUserId,
  isWithinGrace,
  type R2Object,
  truncatedSources,
  unknownPrefixes,
} from "./reconcile.ts";

const NOW = new Date("2026-08-10T12:00:00Z");
const U1 = "11111111-1111-4111-8111-111111111111";
const U2 = "22222222-2222-4222-8222-222222222222";

function obj(key: string, hoursAgo: number): R2Object {
  return { key, lastModified: new Date(NOW.getTime() - hoursAgo * 3600_000) };
}

// --- extractUserId ---------------------------------------------------------

Deno.test("extractUserId: clave bien formada devuelve el uuid", () => {
  assertEquals(extractUserId(`avatars/${U1}/abc.webp`), U1);
});

Deno.test("extractUserId: segundo segmento que no es uuid devuelve null", () => {
  assertEquals(extractUserId("avatars/no-soy-un-uuid/abc.webp"), null);
});

Deno.test("extractUserId: clave fuera de avatars/ devuelve null", () => {
  assertEquals(extractUserId(`panic-buffer/${U1}/abc.webp`), null);
});

Deno.test("extractUserId: clave sin fichero devuelve null", () => {
  assertEquals(extractUserId(`avatars/${U1}/`), null);
});

// --- isWithinGrace ---------------------------------------------------------

Deno.test("isWithinGrace: objeto de hace 1h con gracia 24 esta protegido", () => {
  assertEquals(isWithinGrace(obj("a", 1), NOW, 24), true);
});

Deno.test("isWithinGrace: objeto de hace 25h con gracia 24 NO esta protegido", () => {
  assertEquals(isWithinGrace(obj("a", 25), NOW, 24), false);
});

Deno.test("isWithinGrace: gracia 0 no protege nada", () => {
  assertEquals(isWithinGrace(obj("a", 0), NOW, 0), false);
});

// --- evaluateBrake ---------------------------------------------------------

Deno.test("evaluateBrake: caso sano devuelve null", () => {
  assertEquals(
    evaluateBrake({
      objectsScanned: 100,
      orphansFound: 5,
      referencedCount: 95,
      referencedTruncated: false,
    }),
    null,
  );
});

Deno.test("evaluateBrake: F2 referenciado vacio con objetos en R2 aborta", () => {
  const reason = evaluateBrake({
    objectsScanned: 3,
    orphansFound: 3,
    referencedCount: 0,
    referencedTruncated: false,
  });
  assertEquals(reason, { kind: "abort", reason: "referenced_set_empty" });
});

Deno.test("evaluateBrake: F2 no salta si R2 tambien esta vacio", () => {
  assertEquals(
    evaluateBrake({
      objectsScanned: 0,
      orphansFound: 0,
      referencedCount: 0,
      referencedTruncated: false,
    }),
    null,
  );
});

Deno.test("evaluateBrake: F3 mas de 500 huerfanos ACOTA, no aborta", () => {
  const reason = evaluateBrake({
    objectsScanned: 10_000,
    orphansFound: 501,
    referencedCount: 9_499,
    referencedTruncated: false,
  });
  assertEquals(reason, { kind: "cap", reason: "too_many_orphans" });
});

Deno.test("evaluateBrake: F4 supera el 50% con 100 objetos ACOTA, no aborta", () => {
  const reason = evaluateBrake({
    objectsScanned: 100,
    orphansFound: 60,
    referencedCount: 40,
    referencedTruncated: false,
  });
  assertEquals(reason, { kind: "cap", reason: "orphan_ratio_too_high" });
});

// Este es el caso que hace util el suelo: sin el, el barrido se bloquearia a diario
// en un bucket pequeno y no limpiaria nunca.
Deno.test("evaluateBrake: F4 NO salta por debajo del suelo de 50 objetos", () => {
  assertEquals(
    evaluateBrake({
      objectsScanned: 4,
      orphansFound: 3,
      referencedCount: 1,
      referencedTruncated: false,
    }),
    null,
  );
});

Deno.test("evaluateBrake: F4 justo en el suelo con 50 objetos si evalua", () => {
  const reason = evaluateBrake({
    objectsScanned: 50,
    orphansFound: 30,
    referencedCount: 20,
    referencedTruncated: false,
  });
  assertEquals(reason, { kind: "cap", reason: "orphan_ratio_too_high" });
});

// --- F5: truncamiento del conjunto referenciado ----------------------------
// Este es EL caso que ningun otro freno ve. 1500 avatares vivos, 1500 objetos en R2, cola vacia:
// PostgREST recorta `profiles` a max_rows = 1000 SIN error, 500 fotos vivas parecen huerfanas, y
// F2/F3/F4 dan todas por buena la pasada. `media-gc-cron` las borra en los 5 minutos siguientes.

Deno.test("evaluateBrake: F5 conjunto truncado aborta aunque el resto parezca sano", () => {
  const reason = evaluateBrake({
    objectsScanned: 1500,
    orphansFound: 500,
    referencedCount: 1000,
    referencedTruncated: true,
  });
  assertEquals(reason, { kind: "abort", reason: "referenced_set_truncated" });
});

// Sin F5, exactamente estos numeros pasaban los tres frenos y encolaban 500 borrados.
Deno.test("evaluateBrake: los otros frenos NO ven el truncamiento de 1500/1000", () => {
  const reason = evaluateBrake({
    objectsScanned: 1500,
    orphansFound: 500,
    referencedCount: 1000,
    referencedTruncated: false,
  });
  assertEquals(reason, null);
});

Deno.test("evaluateBrake: F5 tiene prioridad sobre los demas frenos", () => {
  const reason = evaluateBrake({
    objectsScanned: 100,
    orphansFound: 100,
    referencedCount: 0,
    referencedTruncated: true,
  });
  assertEquals(reason, { kind: "abort", reason: "referenced_set_truncated" });
});

// --- truncatedSources ------------------------------------------------------

Deno.test("truncatedSources: totales que cuadran no reportan nada", () => {
  assertEquals(
    truncatedSources([
      { source: "profiles", rowsFetched: 1500, reportedTotal: 1500 },
      { source: "storage_gc_queue", rowsFetched: 0, reportedTotal: 0 },
    ]),
    [],
  );
});

Deno.test("truncatedSources: leer de menos delata el recorte de max_rows", () => {
  assertEquals(
    truncatedSources([
      { source: "profiles", rowsFetched: 1000, reportedTotal: 1500 },
      { source: "storage_gc_queue", rowsFetched: 3, reportedTotal: 3 },
    ]),
    ["profiles"],
  );
});

// Leer de mas solo pasa si la tabla cambio entre paginas, y entonces tampoco se puede afirmar que
// no faltara ninguna fila: se aborta igual.
Deno.test("truncatedSources: leer de mas tambien se considera descuadre", () => {
  assertEquals(
    truncatedSources([{ source: "profiles", rowsFetched: 1001, reportedTotal: 1000 }]),
    ["profiles"],
  );
});

Deno.test("truncatedSources: sin total exacto falla cerrado", () => {
  assertEquals(
    truncatedSources([{ source: "storage_gc_queue", rowsFetched: 12, reportedTotal: null }]),
    ["storage_gc_queue"],
  );
});

Deno.test("truncatedSources: reporta las dos fuentes si las dos descuadran", () => {
  assertEquals(
    truncatedSources([
      { source: "profiles", rowsFetched: 1000, reportedTotal: 4000 },
      { source: "storage_gc_queue", rowsFetched: 1000, reportedTotal: 1200 },
    ]),
    ["profiles", "storage_gc_queue"],
  );
});

// --- unknownPrefixes -------------------------------------------------------

Deno.test("unknownPrefixes: avatars/ es conocido", () => {
  assertEquals(unknownPrefixes(["avatars/"]), []);
});

Deno.test("unknownPrefixes: un prefijo de otra fase se reporta y no se toca", () => {
  assertEquals(unknownPrefixes(["avatars/", "panic-buffer/"]), ["panic-buffer/"]);
});

// --- decideReconcile -------------------------------------------------------

Deno.test("decideReconcile: encola solo lo no referenciado y fuera de gracia", () => {
  const decision = decideReconcile({
    objects: [
      obj(`avatars/${U1}/vivo.webp`, 100),
      obj(`avatars/${U1}/huerfano.webp`, 100),
      obj(`avatars/${U2}/recien-subido.webp`, 1),
    ],
    referenced: new Set([`avatars/${U1}/vivo.webp`]),
    now: NOW,
    graceHours: 24,
    referencedTruncated: false,
  });

  assertEquals(decision.abortedReason, null);
  assertEquals(decision.objectsScanned, 3);
  assertEquals(decision.orphansFound, 1);
  assertEquals(decision.enqueue, [{ key: `avatars/${U1}/huerfano.webp`, userId: U1 }]);
  assertEquals(decision.malformedKeys, []);
});

Deno.test("decideReconcile: clave con uuid invalido cuenta pero no se encola", () => {
  const decision = decideReconcile({
    objects: [obj("avatars/basura/x.webp", 100), obj(`avatars/${U1}/vivo.webp`, 100)],
    referenced: new Set([`avatars/${U1}/vivo.webp`]),
    now: NOW,
    graceHours: 24,
    referencedTruncated: false,
  });

  assertEquals(decision.orphansFound, 1);
  assertEquals(decision.enqueue, []);
  assertEquals(decision.malformedKeys, ["avatars/basura/x.webp"]);
});

// El freno se evalua ANTES de encolar: un abort no debe dejar ni una fila.
Deno.test("decideReconcile: si el freno salta no encola nada", () => {
  const decision = decideReconcile({
    objects: [obj(`avatars/${U1}/a.webp`, 100), obj(`avatars/${U1}/b.webp`, 100)],
    referenced: new Set(),
    now: NOW,
    graceHours: 24,
    referencedTruncated: false,
  });

  assertEquals(decision.abortedReason, "referenced_set_empty");
  assertEquals(decision.enqueue, []);
  assertEquals(decision.orphansFound, 2);
});

// Con el conjunto truncado, la foto viva que se quedo fuera de la pagina PARECE huerfana. Lo unico
// que impide encolarla —y que media-gc-cron la borre de R2 en 5 minutos— es F5.
Deno.test("decideReconcile: conjunto truncado no encola nada aunque haya candidatos claros", () => {
  const decision = decideReconcile({
    objects: [obj(`avatars/${U1}/vivo-fuera-de-pagina.webp`, 100), obj(`avatars/${U2}/vivo.webp`, 100)],
    referenced: new Set([`avatars/${U2}/vivo.webp`]),
    now: NOW,
    graceHours: 24,
    referencedTruncated: true,
  });

  assertEquals(decision.abortedReason, "referenced_set_truncated");
  assertEquals(decision.enqueue, []);
  assertEquals(decision.malformedKeys, []);
});

// --- H-S-03: acotar en vez de abortar --------------------------------------
//
// El ataque que estos tests cierran: `profile-photo-upload-url` no tiene cuota, asi que una cuenta
// cualquiera podia subir 501 objetos sin confirmar (~100 MB). Pasada la gracia, cada pasada
// encontraba >500 huerfanos, abortaba y encolaba CERO. Como los huerfanos nunca bajan solos de 500,
// el estado es absorbente: el barrido quedaba inutilizado PARA SIEMPRE y con el el unico recolector
// que cumple el Art. 17. No hacia falta un atacante — a 10.000 usuarios, un 5 % de abandono mensual
// son ~500/mes.

function orphans(count: number, hoursAgoBase: number): R2Object[] {
  // Antiguedad creciente con el indice para poder afirmar CUALES se eligen al acotar.
  return Array.from(
    { length: count },
    (_, i) => obj(`avatars/${U1}/huerfano-${String(i).padStart(4, "0")}.webp`, hoursAgoBase + i),
  );
}

Deno.test("decideReconcile: F3 acota y SI encola — el barrido no se puede apagar", () => {
  const decision = decideReconcile({
    objects: orphans(501, 48),
    referenced: new Set([...Array(600).keys()].map((i) => `avatars/${U2}/vivo-${i}.webp`)),
    now: NOW,
    graceHours: 24,
    referencedTruncated: false,
  });

  assertEquals(decision.abortedReason, null);
  assertEquals(decision.cappedReason, "too_many_orphans");
  assertEquals(decision.orphansFound, 501);
  // Lo que antes era 0. Que sea > 0 es TODA la correccion: un tope que drena trabajo no es armable.
  assertEquals(decision.enqueue.length, 500);
});

Deno.test("decideReconcile: al acotar elige los MAS ANTIGUOS, no los primeros que lista S3", () => {
  // S3 lista lexicograficamente por clave, y la clave empieza por el user_id. Sin ordenar por
  // fecha, el corte favoreceria siempre a los mismos usuarios y los del final no se limpiarian
  // nunca. Aqui el ultimo por clave (`huerfano-0500`) es el MAS antiguo, asi que tiene que entrar.
  const objects = orphans(501, 48);
  const decision = decideReconcile({
    objects,
    referenced: new Set([`avatars/${U2}/vivo.webp`]),
    now: NOW,
    graceHours: 24,
    referencedTruncated: false,
  });

  const enqueued = new Set(decision.enqueue.map((o) => o.key));
  assertEquals(enqueued.has(`avatars/${U1}/huerfano-0500.webp`), true);
  // Y el mas reciente de todos es justo el que se queda fuera del corte.
  assertEquals(enqueued.has(`avatars/${U1}/huerfano-0000.webp`), false);
});

Deno.test("decideReconcile: acotar NO relaja F5 — un conjunto truncado sigue encolando cero", () => {
  // La distincion que sostiene todo el diseno: F3/F4 acotan porque el conjunto referenciado es
  // fiable y solo hay mucho. F5/F2 dudan del conjunto mismo, asi que un «huerfano» puede ser un
  // avatar vivo. Que F3 tambien se cumpla aqui no puede convertir el aborto en un tope.
  const decision = decideReconcile({
    objects: orphans(600, 48),
    referenced: new Set([`avatars/${U2}/vivo.webp`]),
    now: NOW,
    graceHours: 24,
    referencedTruncated: true,
  });

  assertEquals(decision.abortedReason, "referenced_set_truncated");
  assertEquals(decision.cappedReason, null);
  assertEquals(decision.enqueue, []);
});

Deno.test("decideReconcile: acotar NO relaja F2 — referenciado vacio sigue encolando cero", () => {
  const decision = decideReconcile({
    objects: orphans(600, 48),
    referenced: new Set<string>(),
    now: NOW,
    graceHours: 24,
    referencedTruncated: false,
  });

  assertEquals(decision.abortedReason, "referenced_set_empty");
  assertEquals(decision.cappedReason, null);
  assertEquals(decision.enqueue, []);
});

Deno.test("decideReconcile: pasada sana no marca cappedReason", () => {
  const decision = decideReconcile({
    objects: [obj(`avatars/${U1}/huerfano.webp`, 48), obj(`avatars/${U2}/vivo.webp`, 48)],
    referenced: new Set([`avatars/${U2}/vivo.webp`]),
    now: NOW,
    graceHours: 24,
    referencedTruncated: false,
  });

  assertEquals(decision.abortedReason, null);
  assertEquals(decision.cappedReason, null);
  assertEquals(decision.enqueue.length, 1);
});

// La propiedad que cierra el ataque, dicha como invariante y no como ejemplo: por muchos huerfanos
// que suba un atacante, CADA pasada drena el tope. El barrido nunca se para.
Deno.test("decideReconcile: con 5000 huerfanos el barrido sigue drenando el tope", () => {
  const decision = decideReconcile({
    objects: orphans(5000, 48),
    referenced: new Set([...Array(6000).keys()].map((i) => `avatars/${U2}/vivo-${i}.webp`)),
    now: NOW,
    graceHours: 24,
    referencedTruncated: false,
  });

  assertEquals(decision.cappedReason, "too_many_orphans");
  assertEquals(decision.enqueue.length, 500);
});
