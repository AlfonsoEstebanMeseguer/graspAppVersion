-- Baseline consolidado: sustituye a 20260809120100_seed_catalogs.sql (sin cambios de fondo,
-- solo se mueve). Tabla de correspondencia completa:
-- apps/backend/supabase/migrations/README.md.
--
-- Por qué esto es una migración y no `seed.sql`: `supabase db push` NO ejecuta `seed.sql`
-- contra el proyecto remoto (solo lo aplica `db reset` en local). Los catálogos (categorías,
-- casos concretos, insignias) son datos de los que depende el CÓDIGO —
-- `onboarding-complete` devuelve 422 si el slug no existe—, así que viajan con las
-- migraciones. `seed.sql` queda para fixtures de desarrollo.
--
-- IDEMPOTENTE: todos los insert llevan `on conflict (slug) do nothing`. Correr esta
-- migración dos veces, o sobre una base donde los catálogos ya existan, no duplica ni pisa
-- nada — y por eso también sirve para reconciliar un entorno que ya tenga estas filas.
--
-- Los `slug` son el contrato con el cliente Flutter: las opciones del onboarding envían el
-- slug, no la etiqueta visible ni un id inventado en Dart. Si un slug cambia aquí, cambia en
-- `lib/domain/onboarding/onboarding_question.dart` en el mismo commit.
--
-- Depende de 20260816120000_baseline_schema.sql (categories, experience_cases, badges).

-- ===== CATEGORÍAS (Sección 4 del documento maestro) =====
insert into public.categories (name, slug, parent_id)
values
  ('Relaciones y rupturas', 'relaciones-rupturas', null),
  ('Ansiedad y estrés cotidiano', 'ansiedad-estres', null),
  ('Familia', 'familia', null),
  ('Soledad', 'soledad', null),
  ('Primer empleo', 'primer-empleo', null),
  ('Burnout', 'burnout', null),
  ('Universidad', 'universidad', null),
  ('Cambios de ciudad', 'cambios-ciudad', null),
  ('Migración', 'migracion', null),
  ('Duelo', 'duelo', null),
  ('Autoestima', 'autoestima', null),
  ('Crecimiento personal', 'crecimiento-personal', null)
on conflict (slug) do nothing;

-- ===== CASOS CONCRETOS (pregunta 2 del onboarding) =====
-- No son categorías secundarias: son ejemplos de respuesta en primera persona. `category_id`
-- es el puente hacia el tema de apoyo, y vive aquí (no en Flutter) porque es entrada del
-- algoritmo de afinidad — ver el comentario de la tabla en 20260816120000_baseline_schema.sql.
insert into public.experience_cases (slug, label, category_id, icon, sort_order)
values
  ('ruptura-reciente', 'Rompí con mi pareja',
    (select id from public.categories where slug = 'relaciones-rupturas'), 'heart_broken', 10),
  ('relacion-a-distancia', 'Relación a distancia',
    (select id from public.categories where slug = 'relaciones-rupturas'), 'flight_takeoff', 20),
  ('ansiedad-examenes', 'Ansiedad por estudios',
    (select id from public.categories where slug = 'universidad'), 'school', 30),
  ('ataques-de-panico', 'Pánico',
    (select id from public.categories where slug = 'ansiedad-estres'), 'monitor_heart', 40),
  ('no-duermo-bien', 'Duermo mal',
    (select id from public.categories where slug = 'ansiedad-estres'), 'bedtime', 50),
  ('primer-trabajo', 'Primer trabajo',
    (select id from public.categories where slug = 'primer-empleo'), 'badge', 60),
  ('me-quede-sin-trabajo', 'Me quedé sin trabajo',
    (select id from public.categories where slug = 'primer-empleo'), 'work_off', 70),
  ('agotado-en-el-trabajo', 'Cansancio por el trabajo',
    (select id from public.categories where slug = 'burnout'), 'local_fire_department', 80),
  ('discusiones-en-casa', 'Problemas familiares',
    (select id from public.categories where slug = 'familia'), 'groups', 90),
  ('cuido-de-un-familiar', 'Familiar enfermo',
    (select id from public.categories where slug = 'familia'), 'volunteer_activism', 100),
  ('me-mude-de-ciudad', 'Mudando de ciudad',
    (select id from public.categories where slug = 'cambios-ciudad'), 'location_city', 110),
  ('vivo-en-otro-pais', 'Vivir en el extranjero',
    (select id from public.categories where slug = 'migracion'), 'public', 120),
  ('sin-gente-cerca', 'Me siento solo',
    (select id from public.categories where slug = 'soledad'), 'person_outline', 130),
  ('perdi-a-alguien', 'He perdido a alguien',
    (select id from public.categories where slug = 'duelo'), 'filter_vintage', 140),
  ('no-me-gusto', 'No me gusto',
    (select id from public.categories where slug = 'autoestima'), 'sentiment_dissatisfied', 150),
  ('quiero-cambiar-algo', 'Quiero cambiar',
    (select id from public.categories where slug = 'crecimiento-personal'), 'auto_awesome', 160),
  ('empezando-terapia', 'He empezado terapia',
    (select id from public.categories where slug = 'crecimiento-personal'), 'psychology', 170),
  ('dejando-universidad', 'Dudas sobre estudios',
    (select id from public.categories where slug = 'universidad'), 'menu_book', 180)
on conflict (slug) do nothing;

-- ===== INSIGNIAS =====
-- Catálogo completo: la pantalla de perfil pinta las ganadas en color y el resto en gris tras
-- "Ver todas" (boceto pictures/screens/08-profile.jpeg). Ninguna se concede desde el cliente:
-- `user_badges` no tiene policy de escritura, solo service_role inserta.
insert into public.badges (slug, name, description, icon, sort_order)
values
  ('primeros-pasos', 'Primeros pasos', 'Completaste tu perfil y tu cuestionario de bienvenida.', 'footprint', 10),
  ('primera-sala', 'Primera sala', 'Entraste en tu primera sala de voz.', 'record_voice_over', 20),
  ('buen-oyente', 'Buen oyente', 'Acumulaste 5 horas escuchando a otras personas.', 'hearing', 30),
  ('presencia-constante', 'Presencia constante', 'Mantuviste una racha de 7 días seguidos.', 'local_fire_department', 40),
  ('mano-tendida', 'Mano tendida', 'Alguien te agradeció públicamente tu apoyo.', 'volunteer_activism', 50),
  ('circulo-cercano', 'Círculo cercano', 'Llegaste a 10 personas siguiéndote.', 'group', 60),
  ('voz-serena', 'Voz serena', 'Moderaste una sala sin ninguna incidencia.', 'spa', 70),
  ('constancia', 'Constancia', 'Mantuviste una racha de 30 días seguidos.', 'calendar_month', 80),
  ('refugio', 'Refugio', 'Acumulaste 50 horas escuchando a otras personas.', 'shield_moon', 90),
  ('companero-del-ano', 'Compañero del año', 'Un año acompañando a la comunidad.', 'workspace_premium', 100)
on conflict (slug) do nothing;

-- ROLLBACK (solo datos):
-- delete from public.badges where slug in (
--   'primeros-pasos','primera-sala','buen-oyente','presencia-constante','mano-tendida',
--   'circulo-cercano','voz-serena','constancia','refugio','companero-del-ano');
-- delete from public.experience_cases;
-- delete from public.categories;
