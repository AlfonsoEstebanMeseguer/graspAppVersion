import 'onboarding_catalogs.dart';

/// Contrato de lectura de los catálogos del onboarding (`GET
/// onboarding-catalogs`).
///
/// Separado de [OnboardingRepository] a propósito: uno lee (sin sesión
/// necesariamente activa), el otro escribe (requiere JWT del usuario). Mezclar
/// ambos en una interfaz obligaría a los dobles de test a implementar
/// operaciones que no usan.
abstract interface class OnboardingCatalogsRepository {
  /// Catálogos vigentes de categorías, casos concretos, perfiles de oyente y
  /// fuentes de descubrimiento. Lanza [OnboardingFailure] si el backend no
  /// responde.
  Future<OnboardingCatalogs> getCatalogs();
}