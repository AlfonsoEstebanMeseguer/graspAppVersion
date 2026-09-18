/// Curva de XP para la barra de progreso de `08-profile.jpeg`
/// ("Nivel 12 · 1.250 / 1.800 XP").
///
/// **Solo lectura/presentación.** `profiles.level` y `profiles.xp` son la
/// fuente de verdad (los escribe backend, nunca el cliente — ver CLAUDE.md
/// "el cliente nunca escribe... entitlements"); esta curva no decide ni
/// otorga nada, únicamente calcula cuánto XP hace falta para el *siguiente*
/// nivel a partir del nivel ya conocido, para poder dibujar la barra. Si
/// backend expone su propia tabla de umbrales más adelante, esta función se
/// sustituye por ese dato sin tocar la UI (recibe y devuelve `int`).
abstract final class ProfileLevel {
  const ProfileLevel._();

  /// XP total necesario para completar [level] y pasar al siguiente.
  ///
  /// Progresión lineal simple (1.000 en el nivel 1, +300 por nivel): no hay
  /// diseño de economía de XP todavía (eso es Fase 5+, gamificación), así que
  /// se documenta como aproximación explícita en vez de fingir precisión.
  static int xpToNextLevel(int level) => 1000 + (level - 1) * 300;

  /// Progreso `[0, 1]` dentro del nivel actual, para `LinearProgressIndicator`.
  static double progress(int level, int xp) {
    final int threshold = xpToNextLevel(level);
    if (threshold <= 0) return 0;
    return (xp / threshold).clamp(0, 1).toDouble();
  }
}