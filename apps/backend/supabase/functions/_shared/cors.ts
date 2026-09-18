// Cabeceras CORS comunes a todas las Edge Functions HTTP (app Flutter web/móvil + Studio).
// No se restringe `Access-Control-Allow-Origin` a un dominio concreto porque el cliente Flutter
// no siempre corre en un origin fijo (dev en localhost con puerto variable, apps nativas sin
// origin). La autorización real la hace el JWT, no el origin.
export const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, POST, PATCH, OPTIONS",
};

export function handleCorsPreflight(req: Request): Response | null {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  return null;
}