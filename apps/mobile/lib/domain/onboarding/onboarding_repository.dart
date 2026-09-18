import 'onboarding_answers.dart';

/// Contrato para enviar las respuestas del onboarding al backend.
///
/// La pantalla depende de esta interfaz, nunca del cliente de Supabase
/// (skill `flutter-ui`, punto 1).
abstract interface class OnboardingRepository {
  /// Envía las respuestas a la Edge Function `onboarding-complete`.
  ///
  /// Lanza [OnboardingFailure] si el backend rechaza el envío (slug
  /// desconocido, red caída, etc.).
  Future<void> complete(OnboardingAnswers answers);
}