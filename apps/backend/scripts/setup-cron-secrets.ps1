# Deja el entorno LOCAL listo para que `media-gc-cron` se ejecute de verdad.
#
# Hace dos cosas:
#   1. Crea en Vault el secreto `project_url` que `private.invoke_media_gc_cron()` necesita.
#   2. Publica el SHA-256 del token del cron en `supabase/functions/.env`, que es lo que
#      `requireInternalCaller` compara.
#
# El TOKEN en sí no lo toca nadie: lo genera la propia base de datos en la migración
# 20260810170000 y no sale de ahí. Lo que este script mueve es su HASH, que no es secreto y
# no sirve para autenticarse. Antes este script movía la `service_role key`; ya no maneja
# ningún secreto, que es justamente la mejora.
#
# Hay que reejecutarlo después de cada `supabase db reset`: el reset vacía `vault.secrets` y
# la migración genera un token NUEVO, así que el hash publicado deja de valer y el cron
# responde 401 hasta que se vuelva a publicar.
#
# Uso, desde cualquier directorio:
#     powershell -File apps/backend/scripts/setup-cron-secrets.ps1
#
# Compatible con Windows PowerShell 5.1 (el que hay en esta máquina): nada de `pwsh`,
# de `Join-Path` con tres argumentos ni de operadores `??`/`?:`.

$ErrorActionPreference = 'Stop'

$repoRoot    = Resolve-Path (Join-Path $PSScriptRoot '..\..\..')
$workdir     = Join-Path $repoRoot 'apps\backend'
$envFile     = Join-Path $workdir 'supabase\functions\.env'
$dbContainer = 'supabase_db_backend'

# La URL que se guarda NO es la de `supabase status` (http://127.0.0.1:54321): esa es la del
# host. Quien hace la petición es pg_net desde dentro del contenedor de Postgres, y ahí
# 127.0.0.1 es el propio Postgres. En la red de Docker, Kong responde como `kong:8000`.
$projectUrl = 'http://kong:8000'
$escapedUrl = $projectUrl.Replace("'", "''")

Write-Host 'Creando project_url en Vault...'
$sql = @"
begin;
delete from vault.secrets where name = 'project_url';
select vault.create_secret('$escapedUrl', 'project_url');
commit;
"@
$sql | docker exec -i $dbContainer psql -U postgres -d postgres -v ON_ERROR_STOP=1 --quiet -f - | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'psql falló al escribir project_url en Vault.' }

# El token lo crea la migración. Si no está, es que no se ha aplicado.
Write-Host 'Leyendo el HASH del token del cron (el token en claro nunca sale de la BD)...'
$hashSql = "select encode(extensions.digest(decrypted_secret, 'sha256'), 'hex') from vault.decrypted_secrets where name = 'internal_cron_token';"
$hash = ($hashSql | docker exec -i $dbContainer psql -U postgres -d postgres -At -v ON_ERROR_STOP=1 -f -)
if ($LASTEXITCODE -ne 0) { throw 'psql falló al leer el token del cron.' }

$hash = "$hash".Trim()
if ($hash -notmatch '^[0-9a-f]{64}$') {
    throw "No hay token en Vault. ¿Se ha aplicado la migración 20260810170000? (valor leído: '$hash')"
}

# Se reescribe solo esa clave, respetando el resto del fichero si ya existe.
$lines = @()
if (Test-Path $envFile) {
    $lines = @(Get-Content $envFile | Where-Object { $_ -notmatch '^\s*INTERNAL_CRON_TOKEN_SHA256\s*=' })
}
$lines += "INTERNAL_CRON_TOKEN_SHA256=$hash"

# UTF-8 SIN BOM, obligatorio. `Set-Content -Encoding utf8` en PowerShell 5.1 escribe BOM, y el
# parser de .env del CLI de Supabase lo mete dentro del nombre de la variable:
#   unexpected character "﻿" in variable name near "﻿INTERNAL_CRON_TOKEN_SHA256=..."
# El stack entero se niega a arrancar. Comprobado, no supuesto.
[System.IO.File]::WriteAllLines($envFile, $lines, (New-Object System.Text.UTF8Encoding($false)))

Write-Host ''
Write-Host "Hash publicado en $envFile"
Write-Host 'No es un secreto: es el SHA-256 del token, no sirve para autenticarse.'
Write-Host ''
Write-Host 'IMPORTANTE: `docker restart` NO relee esto. Las variables de un contenedor quedan fijadas'
Write-Host 'en Config.Env cuando se CREA, no cuando arranca; reiniciarlo relanza el proceso con el'
Write-Host 'entorno viejo congelado y el cron sigue dando 401 -- exactamente el mismo sintoma que un'
Write-Host 'hash mal copiado, lo que manda a depurar lo que no es (costo tiempo real de depuracion).'
Write-Host 'Hace falta parar y levantar el stack entero:'
Write-Host '  supabase --workdir apps/backend stop'
Write-Host '  supabase --workdir apps/backend start'
Write-Host ''
Write-Host 'Para comprobar las ejecuciones del cron:'
Write-Host "  docker exec $dbContainer psql -U postgres -d postgres -c ""select status, return_message, start_time from cron.job_run_details where jobid = (select jobid from cron.job where jobname = 'media-gc-cron') order by start_time desc limit 5;"""
