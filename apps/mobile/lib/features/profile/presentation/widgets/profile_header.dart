import 'package:flutter/material.dart';

import '../../../../core/theming/grasp_palette.dart';
import '../../../../core/theming/app_theme.dart';
import '../../../../domain/profile/profile.dart';
import 'profile_avatar.dart';

const List<String> _months = <String>[
  'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
  'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
];

/// Cabecera pública del perfil: avatar, nombre, nivel y fecha de nacimiento —
/// traducción directa de la parte superior de `08-profile.jpeg`. El boceto no
/// dibuja explícitamente la fecha de nacimiento (solo nombre + "Nivel N ·
/// tipo"), pero el encargo de Bloque 2 la pide como confirmación visual de
/// que el dato se guardó — se añade como línea pequeña bajo el nivel, sin año
/// (dato sensible en `profiles_private`, no hace falta exponer la edad exacta
/// aquí; la edad en sí ya se calcula en [Profile.age]).
///
/// El avatar lo pinta [ProfileAvatar], con las tres ramas que puede tener
/// (foto subida → URL firmada, avatar predeterminado → asset local, o la
/// inicial del nombre).
///
/// **Dos gestos distintos sobre la misma esquina**: el lápiz abre la hoja para
/// cambiarlo ([onTapPhoto], decisión 0014) y la foto la abre en grande
/// ([onTapAvatar]). Mirar y cambiar son intenciones distintas; meterlas en el
/// mismo toque obligaría a adivinar cuál se quería.
class ProfileHeader extends StatelessWidget {
  const ProfileHeader({
    super.key,
    required this.profile,
    required this.birthDateMonthDay,
    required this.onTapEdit,
    required this.onTapPhoto,
    required this.onTapAvatar,
  });

  final Profile profile;

  /// "25 de agosto" ya formateado, o `null` si `profiles_private.birth_date`
  /// está a `NULL`.
  final String? birthDateMonthDay;
  final VoidCallback onTapEdit;

  /// El lápiz: **cambia** el avatar (abre la hoja).
  final VoidCallback onTapPhoto;

  /// La foto: **la mira** en grande. Son dos intenciones distintas y por eso son dos gestos.
  final VoidCallback onTapAvatar;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String name = profile.displayName?.trim().isNotEmpty == true
        ? profile.displayName!
        : 'Sin nombre';

    return Column(
      children: <Widget>[
        Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            Semantics(
              button: true,
              label: 'Ver la foto de perfil en grande',
              child: GestureDetector(
                onTap: onTapAvatar,
                child: ProfileAvatar(profile: profile),
              ),
            ),
            Positioned(
              right: -2,
              bottom: -2,
              child: Semantics(
                button: true,
                label: 'Cambiar foto de perfil',
                child: Material(
                  color: context.palette.brand,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: onTapPhoto,
                    child: Padding(
                      padding: EdgeInsets.all(6),
                      child: Icon(
                        Icons.edit_rounded,
                        size: 16,
                        color: context.palette.onBrand,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Semantics(
          button: true,
          label: 'Editar perfil',
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.field),
            onTap: onTapEdit,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(name, style: theme.textTheme.headlineMedium),
                  const SizedBox(width: AppSpacing.xs),
                  Icon(
                    Icons.edit_outlined,
                    size: 16,
                    color: context.palette.iconSoft,
                  ),
                ],
              ),
            ),
          ),
        ),
        // "Oyente Activo" es descriptivo, no un dato de backend: no hay
        // columna de "tipo de oyente" en el esquema de Bloque 1/2. Se
        // hardcodea a propósito (ver instrucciones del bloque) hasta que
        // exista una clasificación real derivada de la actividad.
        Text(
          'Nivel ${profile.level} · Oyente Activo',
          style: theme.textTheme.bodyMedium?.copyWith(color: context.palette.brandStrong),
        ),
        if (birthDateMonthDay != null) ...<Widget>[
          const SizedBox(height: AppSpacing.xs),
          Text(
            birthDateMonthDay!,
            style: theme.textTheme.bodySmall?.copyWith(color: context.palette.textMuted),
          ),
        ],
      ],
    );
  }
}

/// "25 de agosto" a partir de una fecha, sin año (Sección 4 del encargo de
/// Bloque 2: "sin año").
String? formatBirthDateMonthDay(DateTime? birthDate) {
  if (birthDate == null) return null;
  return '${birthDate.day} de ${_months[birthDate.month - 1]}';
}