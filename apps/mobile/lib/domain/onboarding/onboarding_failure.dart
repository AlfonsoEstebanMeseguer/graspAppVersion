/// Error al enviar las respuestas del onboarding al backend, o al leer sus
/// catálogos.
///
/// Deliberadamente simple (un mensaje, no un `enum` de causas como
/// `AuthFailure`): a diferencia del login, aquí no hay ramas de UI distintas
/// por tipo de error — siempre se muestra el mismo mensaje con reintento.
class OnboardingFailure implements Exception {
  const OnboardingFailure(this.message);

  final String message;

  @override
  String toString() => 'OnboardingFailure: $message';
}