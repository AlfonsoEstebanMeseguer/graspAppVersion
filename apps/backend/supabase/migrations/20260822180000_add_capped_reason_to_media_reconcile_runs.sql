-- Distingue una pasada ACOTADA de una ABORTADA en media_reconcile_runs.
--
-- Origen: H-S-03 de la auditoría integral del 2026-08-15
-- (docs/audits/2026-08-15-auditoria-integral/04-seguridad.md).
--
-- Los cuatro frenos de `evaluateBrake` abortaban por igual y encolaban cero. Como
-- `profile-photo-upload-url` no tiene cuota, cualquier cuenta podía subir 501 objetos sin
-- confirmar y dejar el barrido permanentemente inutilizado: los huérfanos nunca bajan solos de
-- 500, así que cada pasada volvía a abortar. Con el barrido apagado, el único recolector que
-- cumple el Art. 17 deja de funcionar.
--
-- Desde ahora los frenos se dividen en dos (ver la cabecera de `evaluateBrake`):
--   · F5/F2 dudan del conjunto referenciado → siguen ABORTANDO, encolando cero. No es negociable:
--     con un conjunto incompleto, un objeto «huérfano» puede ser un avatar vivo.
--   · F3/F4 solo dicen que hay mucho trabajo → ACOTAN: encolan los MAX_ORPHANS_PER_RUN más
--     antiguos y marcan la pasada aquí.
--
-- Por qué una columna nueva y no reutilizar `aborted_reason`: son estados distintos y el consumidor
-- (ops-digest-cron) tiene que poder separarlos. Una pasada abortada no hizo NADA y su
-- `orphans_enqueued` es 0 por invariante; una acotada sí drenó trabajo y es sana, solo incompleta.
-- Meterlas en la misma columna obligaría a mirar `orphans_enqueued` para desambiguar, y haría
-- mentir al comentario de esa columna.

alter table public.media_reconcile_runs
  add column if not exists capped_reason text;

comment on column public.media_reconcile_runs.capped_reason is
  'null = la pasada encoló todo lo que encontró. No null = se acotó: se encolaron los '
  'MAX_ORPHANS_PER_RUN huérfanos más antiguos y el resto espera a la siguiente pasada. '
  'Valores de evaluateBrake (_shared/reconcile.ts, veredicto kind="cap"): too_many_orphans, '
  'orphan_ratio_too_high. NO es un enum cerrado. '
  'DISTINTO de aborted_reason: una pasada acotada es SANA pero incompleta y su orphans_enqueued '
  'es > 0; una abortada no encoló nada y su orphans_enqueued es 0 por invariante. '
  'Que se repita varios días seguidos significa que los huérfanos entran más rápido de lo que el '
  'barrido los drena — señal de abuso o de que MAX_ORPHANS_PER_RUN se quedó corto.';

-- Índice parcial para la consulta del digest: «¿se ha acotado alguna pasada últimamente?».
-- Parcial porque lo normal es que la columna sea null, y así el índice solo pesa lo que pesan las
-- pasadas frenadas — el mismo criterio que idx_media_reconcile_runs_last_ok.
create index if not exists idx_media_reconcile_runs_capped
  on public.media_reconcile_runs (started_at desc)
  where capped_reason is not null;

-- ROLLBACK
-- drop index if exists public.idx_media_reconcile_runs_capped;
-- alter table public.media_reconcile_runs drop column if exists capped_reason;
