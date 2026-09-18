import 'package:flutter/foundation.dart';

/// Una opción de catálogo tal y como la sirve `GET /onboarding-catalogs`:
/// `slug` es lo que viaja de vuelta a `onboarding-complete`, `name` es solo
/// presentación.
@immutable
class CatalogOption {
  const CatalogOption({required this.slug, required this.name});

  final String slug;
  final String name;
}

/// Caso concreto de la pregunta 2 (`experience_cases`). Lleva además
/// `categorySlug` — el tema de apoyo al que apunta — aunque hoy la pantalla no
/// lo usa para filtrar: se conserva porque es dato real del backend y puede
/// justificar agrupar la rejilla por categoría más adelante.
@immutable
class ExperienceCaseOption {
  const ExperienceCaseOption({
    required this.slug,
    required this.name,
    this.categorySlug,
  });

  final String slug;
  final String name;
  final String? categorySlug;
}

/// Respuesta completa de `GET /onboarding-catalogs`.
///
/// `categories` alimenta tanto la pregunta 1 (situación) como la 4
/// (intereses) — mismo catálogo, mismo backend, ver
/// `apps/backend/supabase/functions/onboarding-catalogs/index.ts`.
@immutable
class OnboardingCatalogs {
  const OnboardingCatalogs({
    required this.categories,
    required this.experienceCases,
    required this.listenerProfiles,
    required this.discoverySources,
  });

  final List<CatalogOption> categories;
  final List<ExperienceCaseOption> experienceCases;
  final List<CatalogOption> listenerProfiles;
  final List<CatalogOption> discoverySources;
}