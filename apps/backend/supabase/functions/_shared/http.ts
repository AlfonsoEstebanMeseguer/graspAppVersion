// Helpers de respuesta HTTP comunes. Códigos usados en Grasp (ver .claude/skills/edge-functions/SKILL.md):
//   400 input inválido · 401 no autenticado · 403 no autorizado · 409 conflicto de idempotencia ·
//   422 regla de negocio violada · 500 error interno.
import { corsHeaders } from "./cors.ts";

export class AppError extends Error {
  status: number;
  code: string;
  details?: unknown;

  constructor(status: number, code: string, message: string, details?: unknown) {
    super(message);
    this.status = status;
    this.code = code;
    this.details = details;
  }
}

export function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

export function errorResponse(err: unknown): Response {
  if (err instanceof AppError) {
    return jsonResponse(
      { error: err.code, message: err.message, details: err.details ?? undefined },
      err.status,
    );
  }
  // Nunca se devuelve el stack trace crudo al cliente; se registra en logs de la función.
  console.error("unhandled_error", err);
  return jsonResponse({ error: "internal_error", message: "Error interno" }, 500);
}
