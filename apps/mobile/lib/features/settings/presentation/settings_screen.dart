import 'package:flutter/material.dart';

import '../../../core/theming/app_theme.dart';
import '../../../core/theming/grasp_palette.dart';
import 'widgets/appearance_section.dart';

/// Ajustes de la app.
///
/// ## Boceto
///
/// No tiene uno propio en `pictures/screens/`. Se deriva de `08-profile.jpeg`,
/// que es de donde se entra: cabecera centrada, fondo `canvas` y tarjetas de
/// sección con el mismo radio y la misma sombra que «Insignias» y
/// «Estadísticas». La derivación está anotada en `pictures/screens/README.md`.
///
/// ## Por qué se apila y no es una pestaña
///
/// Igual que `FollowsScreen` y `BlockedUsersScreen`: se abre con
/// `rootNavigator: true` desde el engranaje del perfil, por encima de la barra
/// inferior. Los ajustes son un sitio del que se vuelve, no un quinto destino.
///
/// Hoy contiene **una** sección. Que la pantalla exista con una sola sección es
/// deliberado: el engranaje del perfil llevaba desde el Bloque 2 enseñando un
/// «llega en un próximo bloque», y el sitio donde vive un ajuste de apariencia
/// es Ajustes, no una entrada suelta en el perfil.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  /// Abre la pantalla por encima de la barra inferior.
  static Future<void> open(BuildContext context) {
    return Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext _) => const SettingsScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.palette.canvas,
      appBar: AppBar(title: const Text('Ajustes')),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.gutter,
            AppSpacing.md,
            AppSpacing.gutter,
            AppSpacing.xl,
          ),
          children: const <Widget>[AppearanceSection()],
        ),
      ),
    );
  }
}
