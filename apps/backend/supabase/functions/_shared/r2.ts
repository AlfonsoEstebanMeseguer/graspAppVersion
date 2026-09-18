// Acceso a Cloudflare R2: lectura de credenciales y construcción del cliente S3.
//
// Existe por dos razones, y la segunda es la que importa.
//
// 1. `requireEnv` estaba copiado byte a byte en `profile-avatar-set`, `profile-photo-upload-url` y
//    `profile-photo-view-url`, y `new S3Client({...})` aparecía cinco veces con la misma forma.
//
// 2. Los dos crons NO usaban `requireEnv`: leían las cuatro variables con `Deno.env.get(...)!`. El
//    `!` es una aserción de TypeScript, no una comprobación: en ejecución el valor llega como
//    `undefined` y el SDK lo trata como "no configurado". Con `endpoint` ausente, `S3Client` NO
//    falla — cae a su resolución por defecto y **apunta a Amazon S3**. Es decir: en la función que
//    BORRA ficheros, una variable mal escrita en el panel no daba un error, daba un cliente
//    apuntando al proveedor equivocado. Eso es exactamente el fallo abierto que `CLAUDE.md`
//    prohíbe, en el peor sitio posible para tenerlo.
//
// Regla, entonces: nadie construye un `S3Client` a mano. Se pide aquí, y aquí se falla cerrado.
import { S3Client } from "npm:@aws-sdk/client-s3@3.614.0";
import { AppError } from "./http.ts";

/**
 * Lee una variable de entorno obligatoria.
 *
 * Falla cerrado con 500: sin credenciales se devuelve un error, nunca una respuesta a medias ni un
 * cliente a medio configurar. La cadena vacía cuenta como ausente — es lo que deja un secreto
 * borrado en el panel, y es indistinguible de no haberlo puesto.
 */
export function requireEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) {
    throw new AppError(500, "internal_error", `Falta la variable de entorno ${name}`);
  }
  return value;
}

/**
 * Construye el cliente de R2 con las tres variables que necesita, todas obligatorias.
 *
 * `region: "auto"` es lo que espera R2. El `endpoint` es lo que impide que el SDK resuelva a AWS.
 */
export function createR2Client(): S3Client {
  return new S3Client({
    region: "auto",
    credentials: {
      accessKeyId: requireEnv("CLOUDFLARE_R2_ACCESS_KEY_ID"),
      secretAccessKey: requireEnv("CLOUDFLARE_R2_SECRET_ACCESS_KEY"),
    },
    endpoint: requireEnv("CLOUDFLARE_R2_ENDPOINT"),
  });
}

/**
 * Nombre del bucket de avatares.
 *
 * Nombrado aparte del cliente a propósito: la Fase 10 estrenará `grasp-panic-buffer`, y entonces
 * habrá dos buckets sobre el mismo cliente. Que el bucket no viva dentro de `createR2Client()` es
 * lo que permitirá añadirlo sin tocar a quien ya lo usa.
 */
export function requireAvatarBucket(): string {
  return requireEnv("CLOUDFLARE_R2_BUCKET_NAME");
}
