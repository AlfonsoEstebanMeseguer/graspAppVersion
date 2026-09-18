import 'package:flutter/material.dart';

/// Resuelve `badges.icon` (nombre snake_case guardado en BD, ver
/// `20260809120100_seed_catalogs.sql`) a un `IconData` de Material.
///
/// Se usan iconos en vez de emoji literal (que pedía el encargo original) por
/// consistencia con el resto de la app — ningún otro sitio de Grasp usa
/// emoji como elemento de UI, todo es iconografía Material sobre los tokens
/// de `AppColors` — y por accesibilidad: un `Icon` con `Semantics.label`
/// anuncia el nombre de la insignia a un lector de pantalla, un carácter
/// emoji suelto no siempre lo hace de forma consistente entre plataformas.
IconData badgeIconFor(String? iconName) => switch (iconName) {
  'footprint' => Icons.directions_walk_rounded,
  'record_voice_over' => Icons.record_voice_over_rounded,
  'hearing' => Icons.hearing_rounded,
  'local_fire_department' => Icons.local_fire_department_rounded,
  'volunteer_activism' => Icons.volunteer_activism_rounded,
  'group' => Icons.group_rounded,
  'spa' => Icons.spa_rounded,
  'calendar_month' => Icons.calendar_month_rounded,
  'shield_moon' => Icons.shield_moon_rounded,
  'workspace_premium' => Icons.workspace_premium_rounded,
  _ => Icons.emoji_events_rounded,
};