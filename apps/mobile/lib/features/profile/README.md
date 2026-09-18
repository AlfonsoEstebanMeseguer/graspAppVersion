# features/profile

Perfil propio: cabecera (nombre, nivel, fecha de nacimiento), barra de XP, estadísticas
(salas participadas, tiempo escuchando, seguidores, seguidos), insignias y racha. Edición de datos
(nombre, fecha de nacimiento, género, país) y acceso al feed personalizado (onboarding).
Boceto: `pictures/screens/08-profile.jpeg`.

Todos los números que se muestran hoy tienen columna real: `profiles.level/xp/streak_days/
rooms_joined_count/time_helping_seconds/followers_count/following_count`, `profiles_private.
birth_date/gender/country`, `onboarding_responses.responses` (temas de interés y respuestas
privadas del cuestionario, solo legibles por el propio usuario) y `badges`/`user_badges` (catálogo
+ ganadas, lectura pública por RLS). Ninguno se lee ni se escribe directamente salvo `fetchOwn()` —
la escritura pasa siempre por la Edge Function `profile-update`
(`domain/profile/profile_repository.dart`).

**El avatar está implementado** (P5, 2026-08-13). Se cambia tocando la foto de la cabecera, que abre
una hoja modal con dos acciones: elegir uno de los 8 predeterminados o subir una foto. No hay «quitar
la foto» porque el backend exige exactamente uno de `photo_path` o `preset` — quitarse la foto se
hace eligiendo un dibujo, que además la encola para borrarla de R2 (decisión 0014).

Tres cosas del avatar que conviene no romper:

- **El mime que se declara sale de oler los bytes producidos**, nunca del formato que se pidió. En
  móvil, un dispositivo sin WebP lanza `UnsupportedError`; en web no lanza nada y
  `canvas.toDataURL` devuelve PNG en silencio (medido en Edge). Ver `data/profile/avatar_upload.dart`.
- **La URL firmada se cachea por `photo_path`** (`application/avatar_url_provider.dart`): cambia en
  cada llamada, así que sin caché se volverían a descargar los bytes en cada repintado.
- **El códec entra por inyección** (`ImageCompressor`). `data/profile/flutter_image_compressor.dart`
  es lo único sin tests, y a propósito es diminuto.

La columna legacy `profiles.photo_url` no la lee ni la escribe nadie.

**Pendiente de backend/infra**: cambio de contraseña (requiere un flujo de verificación propio,
deferido a Fase 4+).

**El borrado de cuenta está implementado** (hallazgo H-SV-02 de la auditoría de 2026-08-15: la
cascada RGPD ya existía en backend pero solo se podía disparar a mano desde el panel de Supabase).
Se llega desde un enlace de texto al final del scroll (`_DeleteAccountEntry`), no desde un icono
del `AppBar` como "Cerrar sesión": es una acción irreversible y no debe quedar a un tap de
distancia. Abre `DeleteAccountSheet`, otra hoja modal sin boceto propio (mismo precedente que la
decisión 0014 fijó para el avatar), que pide contraseña **y** la frase "BORRAR MI CUENTA" antes de
habilitar el botón, y explica antes de los campos qué se borra y qué se conserva 90 días
(`photo_audit_log`, obligación legal). Al recibir `200` de `account-delete`, cierra la sesión local
(`AccountDeletionController`) y deja que el `redirect` de `app_router.dart` lleve solo a `/`.
