import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../application/auth_controller.dart';
import 'widgets/auth_flow_view.dart';
import 'widgets/auth_shell.dart';

/// Inicio de sesión con email/teléfono + contraseña.
///
/// No tiene boceto propio: se deriva de `pictures/screens/01-Start_Menu.jpeg`
/// (derivación acordada, ver `pictures/screens/README.md`), conservando fondo,
/// marca, tipografía y escena inferior.
class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AuthShell(
      title: 'Hola de nuevo',
      subtitle: 'Te estábamos esperando. Entra con tu correo y contraseña.',
      child: AuthFlowView(
        intent: AuthIntent.login,
        submitLabel: 'Iniciar sesión',
        footer: AuthFooterLink(
          question: '¿Todavía no tienes cuenta?',
          action: 'Créala',
          onPressed: () => context.pushReplacement(AppRoute.register),
        ),
      ),
    );
  }
}
