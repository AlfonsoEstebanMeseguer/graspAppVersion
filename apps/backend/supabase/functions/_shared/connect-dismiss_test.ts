import { assertEquals } from "https://deno.land/std@0.208.0/assert/mod.ts";
import { type DismissalVerdict, validateDismissal } from "./connect-dismiss.ts";

const YO = "aaaaaaaa-0021-4000-8000-00000000000a";
const OTRO = "bbbbbbbb-0021-4000-8000-00000000000b";

Deno.test("un descarte válido devuelve la fila con el actor como user_id", () => {
  const v = validateDismissal({ actorId: YO, target: OTRO });

  assertEquals(v, {
    ok: true,
    row: { user_id: YO, dismissed_user_id: OTRO },
  } satisfies DismissalVerdict);
});

Deno.test("el user_id sale del JWT, NUNCA del body", () => {
  // El body solo aporta a quién se descarta. Si `user_id` viniera de fuera, cualquiera podría
  // escribir descartes en la lista de otra persona y vaciarle el feed de Conectar.
  const v = validateDismissal({ actorId: YO, target: OTRO });
  if (!v.ok) throw new Error("debería ser válido");
  assertEquals(v.row.user_id, YO);
});

Deno.test("auto-descartarse se rechaza aquí, no en la constraint", () => {
  // El `check` `connect_dismissals_no_self` lo impide igual, pero allí es un 23514 que el handler
  // convierte en 500: un «internal_error» ante algo que quien llama puede corregir.
  assertEquals(validateDismissal({ actorId: YO, target: YO }), {
    ok: false,
    reason: "self_dismiss",
  } satisfies DismissalVerdict);
});

Deno.test("un target que no es uuid se rechaza", () => {
  for (
    const basura of [
      undefined,
      null,
      "",
      "no-soy-un-uuid",
      12345,
      { user: OTRO },
      [OTRO],
      `${OTRO} `, // con espacio al final
      OTRO.slice(0, -1), // un carácter menos
    ]
  ) {
    assertEquals(
      validateDismissal({ actorId: YO, target: basura }),
      { ok: false, reason: "invalid_target" } satisfies DismissalVerdict,
      `no se rechazó: ${JSON.stringify(basura)}`,
    );
  }
});

Deno.test("un uuid en MAYÚSCULAS se acepta y no se normaliza", () => {
  // `isUuid` es insensible a mayúsculas. Postgres compara uuids por valor, no por texto, así que
  // reescribirlo aquí no aportaría nada — y este test fija que no se toca, para que nadie añada un
  // `toLowerCase()` creyendo que hace falta.
  const mayus = OTRO.toUpperCase();
  const v = validateDismissal({ actorId: YO, target: mayus });
  if (!v.ok) throw new Error("debería ser válido");
  assertEquals(v.row.dismissed_user_id, mayus);
});

Deno.test("el orden de las comprobaciones: un target no-uuid gana sobre el auto-descarte", () => {
  // Con `actorId` basura y `target` igual de basura, el motivo tiene que ser `invalid_target`: es
  // el que quien llama puede arreglar mirando su petición. Decir «no puedes descartarte a ti
  // mismo» ante un `target: null` mandaría a corregir lo que no está roto.
  assertEquals(
    validateDismissal({ actorId: "no-uuid", target: "no-uuid" }),
    { ok: false, reason: "invalid_target" } satisfies DismissalVerdict,
  );
});
