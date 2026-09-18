import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../application/auth_controller.dart';
import 'widgets/auth_flow_view.dart';
import 'widgets/auth_shell.dart';

/// Registro con contraseña.
///
/// No tiene boceto propio: se deriva de `pictures/screens/01-Start_Menu.jpeg`
/// (derivación acordada, ver `pictures/screens/README.md`).
///
/// Diferencias reales con Login: aquí sí se crea la cuenta, se piden más datos
/// (nombre, fecha de nacimiento, género) y hay que aceptar los términos.
class RegisterScreen extends StatelessWidget {
  const RegisterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AuthShell(
      title: 'Crea tu cuenta',
      subtitle: 'Completa tus datos y elige una contraseña segura.',
      child: AuthFlowView(
        intent: AuthIntent.signUp,
        submitLabel: 'Crear cuenta',
        requiresTermsAcceptance: true,
        footer: AuthFooterLink(
          question: '¿Ya tienes cuenta?',
          action: 'Inicia sesión',
          onPressed: () => context.pushReplacement(AppRoute.login),
        ),
      ),
    );
  }
}
