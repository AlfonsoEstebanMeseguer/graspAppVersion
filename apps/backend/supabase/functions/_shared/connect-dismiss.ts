// La decisión de «No mostrar más» en Conectar (§6.4, RN-47(6), RN-48).
// PURA: sin red y sin Postgres.
//
// POR QUÉ ESTA FUNCIÓN EXISTE, SIENDO TAN CORTA
// Las dos reglas que decide —el uuid y el auto-descarte— tienen cada una su red de seguridad en la
// base (`connect_dismissals_no_self` y las dos claves ajenas), pero una constraint que salta se
// convierte en un **500**: el cliente recibe «internal_error» ante algo que él mismo puede
// corregir. Decidirlo aquí es lo que hace que salga un 400 con el campo que falla.
//
// Y va en `_shared` y no dentro del handler porque así se prueba sin red ni credenciales, que es la
// regla de esta fase: lo que se puede razonar se testea con `deno test`, y lo que habla con la red
// entra por parámetro.
import { isUuid } from "./validation.ts";

/**
 * Por qué se rechaza un descarte, o `null` si es válido.
 *
 * **No hay variante para «el usuario no existe»**, y es a propósito: eso no se puede saber sin
 * consultar la base, así que lo decide el handler. Meterlo aquí obligaría a pasarle el resultado de
 * una consulta y esta función dejaría de ser pura por un dato que ya viene decidido.
 */
export type DismissalRejection = "invalid_target" | "self_dismiss";

export interface DismissalRequest {
  actorId: string;
  /** Sin tipar: viene del body y se trata como entrada hostil. */
  target: unknown;
}

/** El descarte que se va a escribir, ya validado. */
export interface Dismissal {
  user_id: string;
  dismissed_user_id: string;
}

export type DismissalVerdict =
  | { ok: true; row: Dismissal }
  | { ok: false; reason: DismissalRejection };

/**
 * Valida un descarte y devuelve la fila a escribir.
 *
 * Devuelve un VEREDICTO en vez de lanzar, igual que `evaluateSendLimits`: quien llama decide qué
 * código HTTP le corresponde a cada motivo, y la función se puede probar comparando resultados en
 * vez de capturando excepciones.
 */
export function validateDismissal(req: DismissalRequest): DismissalVerdict {
  if (!isUuid(req.target)) return { ok: false, reason: "invalid_target" };

  // El `check` `connect_dismissals_no_self` también lo impide, pero allí es un 23514 que sube como
  // 500. Aquí es un 400 que dice qué campo está mal.
  if (req.target === req.actorId) return { ok: false, reason: "self_dismiss" };

  return { ok: true, row: { user_id: req.actorId, dismissed_user_id: req.target } };
}
