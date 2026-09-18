import 'package:flutter/foundation.dart';

/// Payload plano que espera `onboarding-complete` desde el 2026-08-09 (ver
/// `apps/backend/supabase/functions/onboarding-complete/index.ts`).
///
/// Todos los campos son slugs de catálogo, no ids inventados ni etiquetas
/// visibles: el backend valida cada uno contra su tabla/lista y responde 422
/// si no reconoce alguno.
@immutable
class OnboardingAnswers {
  const OnboardingAnswers({
    required this.situation,
    required this.experiences,
    required this.profile,
    required this.interests,
    required this.discovery,
  });

  /// Slug de `categories` (pregunta 1).
  final String situation;

  /// Slugs de `experience_cases` (pregunta 2, selección múltiple).
  final List<String> experiences;

  /// Slug de perfil de oyente preferido (pregunta 3).
  final String profile;

  /// Slugs de `categories` reutilizados como temas de interés (pregunta 4,
  /// selección múltiple).
  final List<String> interests;

  /// Slug de fuente de descubrimiento (pregunta 5).
  final String discovery;
}
