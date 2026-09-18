import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theming/grasp_palette.dart';
import '../../../core/theming/app_theme.dart';
import '../../../core/ui/grasp_backdrop.dart';
import '../../../core/ui/grasp_buttons.dart';

/// Términos de Uso.
///
/// **Contenido pendiente**: hoy solo muestra el encabezado. La redacción legal
/// real llega más adelante; lo que ya es definitivo es el contrato de la
/// pantalla, para que el registro pueda depender de él desde ahora.
///
/// Devuelve el veredicto al cerrarse (`context.pop`):
/// - `true`  → el usuario aceptó
/// - `false` → el usuario rechazó
/// - `null`  → salió sin decidir (botón atrás / gesto del sistema), en cuyo caso
///   quien la abrió **no** debe tocar el estado de aceptación.
///
/// No tiene boceto propio en `pictures/screens/`: reutiliza el fondo de
/// `01-Start_Menu.jpeg` igual que Login y Registro (derivación acordada en
/// `pictures/screens/README.md`).
class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      body: GraspBackdrop(
        sceneHeightFactor: 0.30,
        sceneOpacity: 0.45,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.sm,
                ),
                child: IconButton(
                  // Sin argumento: salir por aquí no es ni aceptar ni rechazar.
                  onPressed: () => context.pop(),
                  icon: const Icon(Icons.arrow_back_rounded),
                  color: context.palette.textPrimary,
                  tooltip: 'Volver',
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.gutter,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Text(
                        'Términos de uso',
                        style: theme.textTheme.headlineLarge,
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.gutter,
                  AppSpacing.lg,
                  AppSpacing.gutter,
                  AppSpacing.lg,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    GraspPrimaryButton(
                      label: 'Aceptar',
                      onPressed: () => context.pop(true),
                    ),
                    const SizedBox(height: AppSpacing.md - AppSpacing.xs),
                    GraspSecondaryButton(
                      label: 'Rechazar',
                      onPressed: () => context.pop(false),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
