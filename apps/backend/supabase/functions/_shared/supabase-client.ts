// Fábricas de cliente Supabase para Edge Functions.
//
// Dos clientes, dos propósitos distintos — nunca se mezclan:
//   - `getUserClient(req)`: usa el JWT del header Authorization del propio usuario. Sirve para
//     resolver `auth.getUser()` y para cualquier lectura/escritura que deba respetar RLS.
//   - `getServiceRoleClient()`: usa `SUPABASE_SERVICE_ROLE_KEY`. Se salta RLS — solo para lo que
//     RLS no puede expresar (p. ej. leer `categories` para resolver slugs, o escribir en tablas
//     donde la policy exige columnas que la función deriva, no el cliente). La `service_role key`
//     vive únicamente en variables de entorno del backend; el cliente Flutter nunca la recibe.
import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";
import { AppError } from "./http.ts";

export function getUserClient(req: Request): SupabaseClient {
  const authHeader = req.headers.get("Authorization") ?? "";
  return createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: authHeader } } },
  );
}

export function getServiceRoleClient(): SupabaseClient {
  return createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
}

/**
 * Comparación en tiempo constante. Una comparación normal (`===`) sale en el primer byte que
 * difiere, así que el tiempo de respuesta filtra cuántos bytes del token ha acertado quien
 * llama, y eso permite reconstruirlo byte a byte.
 *
 * La *longitud* sí se filtra, y es deliberado: la longitud de una clave no es secreta, y
 * comparar longitudes primero evita recorrer un array de tamaño variable.
 */
function timingSafeEqual(a: string, b: string): boolean {
  const encoder = new TextEncoder();
  const left = encoder.encode(a);
  const right = encoder.encode(b);
  if (left.length !== right.length) return false;

  let diff = 0;
  for (let i = 0; i < left.length; i++) diff |= left[i] ^ right[i];
  return diff === 0;
}

/** SHA-256 en hexadecimal minúsculo. WebCrypto está en el runtime, sin dependencias. */
async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

/**
 * Autoriza a quien llama a una función *interna* (crons, webhooks internos): exige un token
 * dedicado, generado por la base de datos y compartido solo con pg_cron a través de Vault.
 *
 * POR QUÉ UN TOKEN DEDICADO Y NO LA CLAVE DE SERVICIO
 * Antes esto comparaba contra `SUPABASE_SERVICE_ROLE_KEY`, y esa premisa se rompió sola: el
 * 2026-08-10 Supabase cambió lo que inyecta en esa variable (pasó del JWT legacy `eyJ…` a una
 * clave del formato nuevo `sb_secret_…`) y el cron empezó a devolver 401 sin que nadie tocara
 * el código. Verificado comparando el SHA-256 de la variable con el de Vault, no deducido.
 *
 * Atar la autenticación de un cron a una variable cuyo contenido decide la plataforma es
 * frágil por construcción. Además obligaba a mandar por HTTP, cada 5 minutos, una credencial
 * con acceso total a la base de datos: si se filtraba de un log o un proxy, se perdía todo.
 * Con un token dedicado el radio de impacto se reduce a "alguien puede disparar el GC".
 *
 * POR QUÉ SE COMPARA EL HASH Y NO EL TOKEN
 * El entorno de la función guarda únicamente el SHA-256 (`INTERNAL_CRON_TOKEN_SHA256`); el
 * token en claro no sale nunca de la base de datos. Así el secreto no viaja al panel, ni a un
 * `secrets set`, ni a un transcript: lo que se copia entre sistemas es un hash, que no sirve
 * para autenticarse. Invertirlo exigiría romper SHA-256.
 *
 * La comparación sigue siendo en tiempo constante aunque se comparen hashes. No es necesario
 * —recuperar el token desde su hash exigiría una preimagen— pero cuesta nada y evita tener que
 * razonarlo otra vez el día que alguien reutilice esta función para comparar otra cosa.
 *
 * Falla cerrado: si `INTERNAL_CRON_TOKEN_SHA256` no está en el entorno, se rechaza la llamada.
 * Un despliegue mal configurado debe quedar inservible, nunca abierto.
 *
 * Estas funciones llevan `verify_jwt = false` en `config.toml`: el token no es un JWT, así que
 * el gateway lo rechazaría antes de llegar aquí. Esta comprobación es entonces la ÚNICA capa
 * de autenticación, y por eso falla cerrado en todos los caminos.
 */
export async function requireInternalCaller(req: Request): Promise<void> {
  const expectedHash = Deno.env.get("INTERNAL_CRON_TOKEN_SHA256")?.trim().toLowerCase();
  if (!expectedHash) {
    console.error("INTERNAL_CRON_TOKEN_SHA256 ausente: se rechaza la llamada interna");
    throw new AppError(500, "internal_error", "Error interno");
  }

  const header = req.headers.get("Authorization") ?? "";
  const token = header.startsWith("Bearer ") ? header.slice(7).trim() : "";
  if (token.length === 0) {
    throw new AppError(401, "unauthorized", "Llamada interna no autorizada");
  }

  if (!timingSafeEqual(await sha256Hex(token), expectedHash)) {
    throw new AppError(401, "unauthorized", "Llamada interna no autorizada");
  }
}

/**
 * Resuelve el usuario autenticado a partir del JWT del request. Nunca se confía en un `user_id`
 * enviado en el body: el único origen de verdad es el token verificado.
 */
export async function requireAuthUser(
  req: Request,
): Promise<{ userId: string; email: string | null; client: SupabaseClient }> {
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    throw new AppError(401, "unauthorized", "Falta la cabecera Authorization");
  }

  const client = getUserClient(req);
  const { data, error } = await client.auth.getUser();

  if (error || !data.user) {
    throw new AppError(401, "unauthorized", "Token inválido o expirado");
  }

  // `email` viene del usuario resuelto por el servidor de auth, NUNCA del body: es lo que permite
  // a `account-delete` reautenticar con contraseña sin fiarse de a quién dice el cliente que borra.
  // Puede ser null (la decisión 0005 dejó el alta sin verificación de correo), así que quien lo use
  // tiene que tratar ese caso, no asumirlo.
  return { userId: data.user.id, email: data.user.email ?? null, client };
}