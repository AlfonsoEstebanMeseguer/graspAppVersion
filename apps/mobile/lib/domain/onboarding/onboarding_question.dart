import 'package:flutter/material.dart';

import 'onboarding_catalogs.dart';

// Nota de capas: lo estricto sería que `domain` no conociera `IconData`
// (eso es presentación). Se acepta aquí a propósito, como ya hacía la versión
// anterior de este fichero: los slugs de catálogo llegan del backend, pero el
// icono que les corresponde es contenido de producto estable (no cambia con
// cada respuesta del cuestionario), y separar "id de icono" de "IconData de
// Material" para ~40 opciones sin assets SVG propios es indirección sin
// beneficio real hoy. Si el backend empieza a devolver un campo `icon`
// consistente para categories/listener_profiles/discovery_sources (hoy solo
// `experience_cases` lo tiene en BD, y `onboarding-catalogs` ni siquiera lo
// selecciona), este mapeo se sustituye por ese dato.

/// Una opción seleccionable dentro de una [OnboardingQuestion].
///
/// `slug` es lo que viaja al backend en el payload de `onboarding-complete`
/// (estable aunque cambie la etiqueta visible); `label` e `icon` son solo
/// presentación.
@immutable
class OnboardingOption {
  const OnboardingOption({
    required this.slug,
    required this.label,
    required this.icon,
  });

  final String slug;
  final String label;
  final IconData icon;
}

/// Una pregunta del onboarding (`02-onboarding-questions.jpeg`).
///
/// `key` es el nombre de campo del payload plano que espera
/// `onboarding-complete` (`situation`, `experiences`, `profile`, `interests`,
/// `discovery`) — no un id de contenido interno.
@immutable
class OnboardingQuestion {
  const OnboardingQuestion({
    required this.key,
    required this.title,
    required this.subtitle,
    required this.options,
    this.multiSelect = false,
  });

  final String key;
  final String title;
  final String subtitle;
  final List<OnboardingOption> options;
  final bool multiSelect;
}

/// Construye las 5 preguntas del onboarding a partir de los catálogos
/// servidos por `GET onboarding-catalogs`.
///
/// Contrato completo de `onboarding-complete` (2026-08-09): el body es plano,
/// `{situation, experiences, profile, interests, discovery}`, y cada campo es
/// un slug de catálogo — ver
/// `apps/backend/supabase/functions/onboarding-complete/index.ts`. El orden y
/// las claves de esta lista son exactamente esos 5 campos, en el mismo orden.
abstract final class OnboardingQuestions {
  const OnboardingQuestions._();

  static List<OnboardingQuestion> build(OnboardingCatalogs catalogs) {
    return <OnboardingQuestion>[
      OnboardingQuestion(
        key: 'situation',
        title: '¿Con qué situación te describes mejor?',
        subtitle: 'Elige la que más se parezca a lo que vives ahora',
        options: <OnboardingOption>[
          for (final CatalogOption category in catalogs.categories)
            OnboardingOption(
              slug: category.slug,
              label: category.name,
              icon: _categoryIcon(category.slug),
            ),
        ],
      ),
      OnboardingQuestion(
        key: 'experiences',
        title: '¿Alguna vez has pasado por alguna de estas situaciones?',
        subtitle: 'Puedes elegir varias opciones',
        multiSelect: true,
        options: <OnboardingOption>[
          for (final ExperienceCaseOption experience in catalogs.experienceCases)
            OnboardingOption(
              slug: experience.slug,
              label: experience.name,
              icon: _experienceIcon(experience.slug),
            ),
        ],
      ),
      OnboardingQuestion(
        key: 'profile',
        title: '¿Qué perfil te gustaría que te recomendásemos?',
        subtitle: 'Elige el que más te inspire confianza',
        options: <OnboardingOption>[
          for (final CatalogOption profile in catalogs.listenerProfiles)
            OnboardingOption(
              slug: profile.slug,
              label: profile.name,
              icon: _listenerProfileIcon(profile.slug),
            ),
        ],
      ),
      OnboardingQuestion(
        key: 'interests',
        title: '¿Cuáles son tus temas de interés?',
        subtitle: 'Puedes elegir varias opciones',
        multiSelect: true,
        options: <OnboardingOption>[
          for (final CatalogOption category in catalogs.categories)
            OnboardingOption(
              slug: category.slug,
              label: category.name,
              icon: _categoryIcon(category.slug),
            ),
        ],
      ),
      OnboardingQuestion(
        key: 'discovery',
        title: '¿Cómo descubriste esta aplicación?',
        subtitle: 'Elige una opción',
        options: <OnboardingOption>[
          for (final CatalogOption source in catalogs.discoverySources)
            OnboardingOption(
              slug: source.slug,
              label: source.name,
              icon: _discoveryIcon(source.slug),
            ),
        ],
      ),
    ];
  }

  /// Icono por defecto para un slug que el mapeo no reconoce (catálogo nuevo
  /// en backend sin desplegar todavía en el cliente). Mejor un icono neutro
  /// que romper la pantalla.
  static const IconData _fallbackIcon = Icons.circle_outlined;

  static IconData _categoryIcon(String slug) =>
      switch (slug) {
        'relaciones-rupturas' => Icons.favorite_border_rounded,
        'ansiedad-estres' => Icons.self_improvement_rounded,
        'familia' => Icons.groups_outlined,
        'soledad' => Icons.person_outline_rounded,
        'primer-empleo' => Icons.work_outline_rounded,
        'burnout' => Icons.local_fire_department_outlined,
        'universidad' => Icons.school_outlined,
        'cambios-ciudad' => Icons.location_city_outlined,
        'migracion' => Icons.public_outlined,
        'duelo' => Icons.volunteer_activism_outlined,
        'autoestima' => Icons.emoji_emotions_outlined,
        'crecimiento-personal' => Icons.psychology_outlined,
        _ => _fallbackIcon,
      };

  static IconData _experienceIcon(String slug) =>
      switch (slug) {
        'ruptura-reciente' => Icons.heart_broken_outlined,
        'relacion-a-distancia' => Icons.flight_takeoff_rounded,
        'ansiedad-examenes' => Icons.school_outlined,
        'ataques-de-panico' => Icons.monitor_heart_outlined,
        'no-duermo-bien' => Icons.bedtime_outlined,
        'primer-trabajo' => Icons.badge_outlined,
        'me-quede-sin-trabajo' => Icons.work_off_outlined,
        'agotado-en-el-trabajo' => Icons.local_fire_department_outlined,
        'discusiones-en-casa' => Icons.groups_outlined,
        'cuido-de-un-familiar' => Icons.volunteer_activism_outlined,
        'me-mude-de-ciudad' => Icons.location_city_outlined,
        'vivo-en-otro-pais' => Icons.public_outlined,
        'sin-gente-cerca' => Icons.person_outline_rounded,
        'perdi-a-alguien' => Icons.local_florist_outlined,
        'no-me-gusto' => Icons.sentiment_dissatisfied_outlined,
        'quiero-cambiar-algo' => Icons.auto_awesome_outlined,
        'empezando-terapia' => Icons.psychology_outlined,
        'dejando-universidad' => Icons.menu_book_outlined,
        _ => _fallbackIcon,
      };

  static IconData _listenerProfileIcon(String slug) =>
      switch (slug) {
        'empatico-cercano' => Icons.favorite_rounded,
        'directo-practico' => Icons.bolt_rounded,
        'espiritual-reflexivo' => Icons.self_improvement_rounded,
        'experiencia-similar' => Icons.groups_outlined,
        'formacion-profesional' => Icons.school_outlined,
        'cualquiera' => Icons.shuffle_rounded,
        _ => _fallbackIcon,
      };

  static IconData _discoveryIcon(String slug) =>
      switch (slug) {
        'redes-sociales' => Icons.share_outlined,
        'amigo-familiar' => Icons.group_outlined,
        'busqueda-tienda' => Icons.search_rounded,
        'publicidad' => Icons.campaign_outlined,
        'otro' => Icons.more_horiz_rounded,
        _ => _fallbackIcon,
      };
}