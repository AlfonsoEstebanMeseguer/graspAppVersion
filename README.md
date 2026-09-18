# Grasp

App móvil (iOS/Android) de salas de voz de apoyo entre iguales, organizadas por categoría de experiencia
(rupturas, ansiedad, soledad, duelo, etc.), con mensajería directa 1:1, regalos virtuales, suscripción VIP,
moderación con reputación/reportes/botón de pánico y gamificación.

No hay IA conversacional, ni feed de contenido tipo red social, ni videollamada: todo gira en torno a la sala
de voz, complementada por mensajería directa para profundizar conexiones fuera de la sala.

## Documentación

- [`docs/README.md`](docs/README.md) — **índice completo de `docs/`**: qué documento es la fuente de verdad de
  cada tema, cuáles son instantáneas históricas que no describen el sistema de hoy, y qué manda cuando dos
  documentos se contradicen. Empieza por aquí si no sabes cuál de los 60+ ficheros abrir.
- [`docs/SETUP.md`](docs/SETUP.md) — **montar el repo en una máquina nueva**: dependencias, los tres `.env`
  que no viajan en git, stack local de Supabase, MCPs y plugins de Claude Code.
- [`docs/Grasp-ClaudeCode-Bootstrap.md`](docs/Grasp-ClaudeCode-Bootstrap.md) — **documento maestro**: producto,
  arquitectura, esquema de BD, seguridad, agentes/skills, orden de fases. Input ejecutable para Claude Code.
- [`docs/Grasp-Fase1.md`](docs/Grasp-Fase1.md) — plan operativo detallado de los primeros bloques (entorno,
  Auth, feed personalizado, perfil).
- [`docs/Grasp-Design.md`](docs/Grasp-Design.md) — documento de negocio original (referencia histórica).
- [`docs/db-schema.md`](docs/db-schema.md) — esquema de base de datos.
- [`docs/api-contracts.md`](docs/api-contracts.md) — contratos de las Edge Functions.
- [`docs/decisions/`](docs/decisions/) — decisiones técnicas registradas (ADRs), incluidos desacuerdos.

Ambos documentos maestro y de Fase 1 son **"vivos"**: se actualizan cada vez que se detecta un fallo, una
mejora de seguridad o una lección de implementación (ver Sección 0.2 del documento maestro).

## Stack

Flutter (móvil) · Supabase (Auth, Postgres, Realtime, Storage, Edge Functions) · LiveKit Cloud (voz, detrás de
una interfaz `VoiceService` intercambiable) · Redis (cache/rate limiting) · Cloudflare (CDN/WAF/Turnstile/R2)
· RevenueCat (IAP) · PostHog (analytics) · Sentry (errores). Detalle completo en la Sección 3 del documento
maestro.

## Estructura del monorepo

```
grasp/
├── .claude/            # CLAUDE.md, AGENTS.md, agentes y skills de Claude Code
├── pictures/            # bocetos/mockups de referencia para frontend-agent
├── apps/
│   ├── mobile/          # Flutter
│   └── backend/          # proyecto Supabase (migraciones, Edge Functions, seed)
├── infra/               # Cloudflare, Redis
├── docs/                 # documentación viva del proyecto
└── .github/workflows/    # CI
```

Detalle completo: Sección 2 del documento maestro.

## Estado actual

Bloques 0–2 hechos y **Bloque 3 parcial**. Entorno verificado, app Flutter real en `apps/mobile`, proyecto
Supabase enlazado con 18 migraciones aplicadas y **10 Edge Functions implementadas** (hay 20 directorios: los
otros 10 son solo un `README.md`), y el ciclo completo de la foto de perfil sobre Cloudflare R2
(subir → confirmar → servir → borrar en cascada), con sus crons de recogida de basura y reconciliación.

Desde el 2026-08-16 existe además el **borrado de cuenta** (`account-delete`), que no existía pese a
estar toda su cascada construida: sin él no se puede publicar en App Store ni en Google Play.

**Del Bloque 3 falta la mitad de su Definition of Done** (auditoría del 2026-08-15): no existen las tablas
`user_follows` ni `activity_streaks`, y `follow-toggle` y `match-feed` siguen siendo directorios con un
`README.md`. En consecuencia, los contadores del perfil (seguidores, racha, nivel, XP, salas) están a cero de
forma permanente porque nada los escribe. Detalle y plan de remediación en
[`docs/audits/2026-08-15-auditoria-integral/`](docs/audits/2026-08-15-auditoria-integral/).

En curso: **P5, la UI del avatar** (rama `feat/p5-ui-del-avatar`) — hoja modal para elegir avatar, encuadre
previo a la subida y los ocho avatares de marca.

El siguiente paso siempre sale de [`docs/Grasp-Fase1.md`](docs/Grasp-Fase1.md).
[`docs/BLOQUE1-STATUS.md`](docs/BLOQUE1-STATUS.md) y [`docs/BLOQUE2-STATUS.md`](docs/BLOQUE2-STATUS.md)
detallan cómo se cerró cada bloque, pero son **instantáneas de su fecha**, no el estado de hoy: cada una
lleva en cabecera la lista de lo que ya no es cierto.

## Comandos

- Backend: `supabase start`, `supabase db push`, `supabase functions deploy <fn>`
- Mobile: `flutter run`, `flutter test`, `flutter build ios|apk`
- CI: ⛔ **no existe todavía**. `.github/workflows/` solo contiene un `README.md` con el plan. Hay 281 tests
  automáticos en verde (130 Flutter + 151 Deno) y **nada los ejecuta al abrir un PR**: hay que correrlos a
  mano. Es la deuda de proceso más barata de saldar del proyecto — ver la auditoría del 2026-08-15.

## Convención de nombres

El producto se llama **Grasp** (antes "Abrazo"). Cualquier referencia a "Abrazo" en código, base de datos,
assets o copys debe sustituirse por "Grasp" — checklist completo en la Sección 23 del documento maestro.
