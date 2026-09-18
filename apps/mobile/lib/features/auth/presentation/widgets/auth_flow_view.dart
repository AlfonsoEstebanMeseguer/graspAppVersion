import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/theming/grasp_palette.dart';
import '../../../../core/theming/app_theme.dart';
import '../../../../core/ui/grasp_buttons.dart';
import '../../../../core/ui/staggered_reveal.dart';
import '../../application/auth_controller.dart';
import 'auth_failure_message.dart';
import 'grasp_field.dart';

/// El formulario de autenticación con contraseña.
///
/// Flujo de login: identifier → password
/// Flujo de registro: registerDetails → identifier → password
///
/// Se usa una única pantalla para ambos flujos, con transiciones entre steps,
/// para que el usuario no pierda contexto.
class AuthFlowView extends ConsumerStatefulWidget {
  const AuthFlowView({
    super.key,
    required this.intent,
    required this.submitLabel,
    required this.footer,
    this.requiresTermsAcceptance = false,
  });

  final AuthIntent intent;
  final String submitLabel;
  final Widget footer;
  final bool requiresTermsAcceptance;

  @override
  ConsumerState<AuthFlowView> createState() => _AuthFlowViewState();
}

class _AuthFlowViewState extends ConsumerState<AuthFlowView> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _dateController = TextEditingController();
  final TextEditingController _identifierController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _passwordConfirmController =
      TextEditingController();

  String? _selectedGender;
  DateTime? _selectedDate;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _dateController.dispose();
    _identifierController.dispose();
    _passwordController.dispose();
    _passwordConfirmController.dispose();
    super.dispose();
  }

  AuthController get _controller =>
      ref.read(authControllerProvider(widget.intent).notifier);

  /// Abre los Términos de Uso y aplica el veredicto.
  ///
  /// `null` significa que el usuario salió sin pulsar ninguno de los dos
  /// botones: en ese caso se respeta lo que ya tuviera marcado.
  Future<void> _openTerms() async {
    final bool? accepted = await context.push<bool>(AppRoute.terms);
    if (accepted == null || !mounted) return;
    _controller.setAcceptedTerms(accepted: accepted);
  }

  Future<void> _submitRegisterDetails() async {
    FocusScope.of(context).unfocus();
    // El nombre entraba sin comprobar: se validaban fecha y género y él no. Desde
    // 20260817090000 es `not null` en la base de datos, así que sin esto el alta
    // fallaría en el trigger y el usuario vería un error opaco en vez de saber qué
    // campo le falta.
    final String displayName = _nameController.text.trim();
    if (displayName.isEmpty || _selectedDate == null || _selectedGender == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Completa todos los campos.')),
      );
      return;
    }

    // `runes` cuenta puntos de código, igual que `char_length` en Postgres. `length`
    // contaría unidades UTF-16 y discreparía de la constraint en cuanto hubiera un emoji.
    if (displayName.runes.length > 60) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El nombre no puede pasar de 60 caracteres.')),
      );
      return;
    }

    // El gate real de los términos. `requiresTermsAcceptance` solo pintaba la
    // casilla; sin esto, marcarla o no daba exactamente igual.
    if (widget.requiresTermsAcceptance &&
        !ref.read(authControllerProvider(widget.intent)).acceptedTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Acepta los Términos de Uso para continuar.'),
        ),
      );
      return;
    }

    _controller.updateRegisterDetails(
      displayName: displayName,
      birthDate: _selectedDate,
      gender: _selectedGender,
    );

    _identifierController.text = _emailController.text;
    _controller.submitIdentifier(_emailController.text);
  }

  Future<void> _submitIdentifier() async {
    FocusScope.of(context).unfocus();
    await _controller.submitIdentifier(_identifierController.text);
  }

  Future<void> _submitPassword() async {
    FocusScope.of(context).unfocus();
    final bool ok = await _controller.submitPassword(
      _passwordController.text,
      _passwordConfirmController.text,
    );
    if (ok && mounted) {
      _passwordController.clear();
      _passwordConfirmController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final AuthFormState state = ref.watch(
      authControllerProvider(widget.intent),
    );

    return AnimatedSwitcher(
      duration: GraspMotion.of(context).medium,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (Widget? current, List<Widget> previous) => Stack(
        alignment: Alignment.topCenter,
        children: <Widget>[...previous, ?current],
      ),
      child: switch (state.step) {
        AuthStep.registerDetails => _RegisterDetailsStep(
          key: const ValueKey<String>('registerDetails'),
          state: state,
          nameController: _nameController,
          emailController: _emailController,
          dateController: _dateController,
          onDateChanged: (DateTime date) => _selectedDate = date,
          selectedGender: _selectedGender,
          onGenderChanged: (String? gender) =>
              setState(() => _selectedGender = gender),
          requiresTermsAcceptance: widget.requiresTermsAcceptance,
          onTermsChanged: (bool accepted) =>
              _controller.setAcceptedTerms(accepted: accepted),
          onReadTerms: _openTerms,
          footer: widget.footer,
          onSubmit: _submitRegisterDetails,
        ),
        AuthStep.identifier => _IdentifierStep(
          key: const ValueKey<String>('identifier'),
          state: state,
          controller: _identifierController,
          submitLabel: widget.submitLabel,
          footer: widget.footer,
          onSubmit: _submitIdentifier,
          onBack: () {
            _controller.backToPreviousStep();
          },
        ),
        AuthStep.password => _PasswordStep(
          key: const ValueKey<String>('password'),
          state: state,
          passwordController: _passwordController,
          passwordConfirmController: _passwordConfirmController,
          isSignUp: widget.intent == AuthIntent.signUp,
          onSubmit: _submitPassword,
          onBack: () {
            _controller.backToPreviousStep();
          },
        ),
      },
    );
  }
}

class _RegisterDetailsStep extends StatelessWidget {
  const _RegisterDetailsStep({
    super.key,
    required this.state,
    required this.nameController,
    required this.emailController,
    required this.dateController,
    required this.onDateChanged,
    required this.selectedGender,
    required this.onGenderChanged,
    required this.requiresTermsAcceptance,
    required this.onTermsChanged,
    required this.onReadTerms,
    required this.footer,
    required this.onSubmit,
  });

  final AuthFormState state;
  final TextEditingController nameController;
  final TextEditingController emailController;
  final TextEditingController dateController;
  final ValueChanged<DateTime> onDateChanged;
  final String? selectedGender;
  final ValueChanged<String?> onGenderChanged;
  final bool requiresTermsAcceptance;
  final ValueChanged<bool> onTermsChanged;
  final VoidCallback onReadTerms;
  final Widget footer;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return StaggeredReveal(
      interval: const Duration(milliseconds: 70),
      children: <Widget>[
        GraspField(
          label: 'Tu nombre',
          controller: nameController,
          enabled: !state.isBusy,
          hintText: 'Juan García',
          prefixIcon: Icons.person_outline_rounded,
          keyboardType: TextInputType.name,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: AppSpacing.md),
        GraspField(
          label: 'Tu correo',
          controller: emailController,
          enabled: !state.isBusy,
          hintText: 'tu@correo.com',
          prefixIcon: Icons.mail_outline_rounded,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: AppSpacing.md),
        GraspDateField(
          label: 'Tu fecha de nacimiento',
          controller: dateController,
          onChanged: onDateChanged,
        ),
        const SizedBox(height: AppSpacing.md),
        _GenderSelector(
          value: selectedGender,
          onChanged: onGenderChanged,
          enabled: !state.isBusy,
        ),
        const SizedBox(height: AppSpacing.md),
        AuthFailureBanner(failure: state.failure),
        if (requiresTermsAcceptance) ...<Widget>[
          const SizedBox(height: AppSpacing.md),
          _TermsCheckbox(
            value: state.acceptedTerms,
            enabled: !state.isBusy,
            onChanged: onTermsChanged,
            onRead: onReadTerms,
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        GraspPrimaryButton(
          label: 'Continuar',
          isLoading: state.isSubmitting,
          onPressed: state.isBusy ? null : onSubmit,
        ),
        const SizedBox(height: AppSpacing.xl),
        footer,
      ],
    );
  }
}

class _IdentifierStep extends StatelessWidget {
  const _IdentifierStep({
    super.key,
    required this.state,
    required this.controller,
    required this.submitLabel,
    required this.footer,
    required this.onSubmit,
    required this.onBack,
  });

  final AuthFormState state;
  final TextEditingController controller;
  final String submitLabel;
  final Widget footer;
  final VoidCallback onSubmit;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return StaggeredReveal(
      interval: const Duration(milliseconds: 70),
      children: <Widget>[
        AuthFailureBanner(failure: state.failure),
        GraspField(
          label: 'Tu correo',
          controller: controller,
          enabled: !state.isBusy,
          hintText: 'tu@correo.com',
          prefixIcon: Icons.mail_outline_rounded,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.go,
          autofillHints: const <String>[AutofillHints.email],
          onSubmitted: (_) {
            if (!state.isBusy) onSubmit();
          },
        ),
        const SizedBox(height: AppSpacing.lg),
        GraspPrimaryButton(
          label: submitLabel,
          isLoading: state.isSubmitting,
          onPressed: state.isBusy ? null : onSubmit,
        ),
        const SizedBox(height: AppSpacing.xl),
        footer,
      ],
    );
  }
}

class _PasswordStep extends StatelessWidget {
  const _PasswordStep({
    super.key,
    required this.state,
    required this.passwordController,
    required this.passwordConfirmController,
    required this.isSignUp,
    required this.onSubmit,
    required this.onBack,
  });

  final AuthFormState state;
  final TextEditingController passwordController;
  final TextEditingController passwordConfirmController;
  final bool isSignUp;
  final VoidCallback onSubmit;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return StaggeredReveal(
      interval: const Duration(milliseconds: 70),
      children: <Widget>[
        Text.rich(
          TextSpan(
            children: <InlineSpan>[
              // El MISMO paso sirve para registrarse y para entrar, y el texto
              // no puede ser el mismo: a quien vuelve no se le pide que "cree"
              // la contraseña que ya tiene. `isSignUp` ya llegaba aquí y se
              // usaba dos líneas más abajo para el `textInputAction`; lo que
              // faltaba era usarlo también para lo que el usuario LEE.
              TextSpan(
                text: isSignUp
                    ? 'Crea una contraseña para '
                    : 'Introduce tu contraseña para ',
              ),
              TextSpan(
                text: state.identifier,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: context.palette.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: AppSpacing.lg),
        AuthFailureBanner(failure: state.failure),
        GraspPasswordField(
          label: 'Contraseña',
          controller: passwordController,
          enabled: !state.isBusy,
          autofocus: true,
          hintText: 'Al menos 8 caracteres',
          textInputAction: isSignUp ? TextInputAction.next : TextInputAction.go,
          onSubmitted: isSignUp ? null : (_) => onSubmit(),
        ),
        if (isSignUp) ...<Widget>[
          const SizedBox(height: AppSpacing.md),
          GraspPasswordField(
            label: 'Confirmar contraseña',
            controller: passwordConfirmController,
            enabled: !state.isBusy,
            hintText: 'Repite tu contraseña',
            textInputAction: TextInputAction.go,
            onSubmitted: (_) => onSubmit(),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        GraspPrimaryButton(
          label: 'Continuar',
          isLoading: state.isSubmitting,
          onPressed: state.isBusy ? null : onSubmit,
        ),
        const SizedBox(height: AppSpacing.md - AppSpacing.xs),
        TextButton(
          onPressed: state.isBusy ? null : onBack,
          child: const Text('Cambiar datos'),
        ),
      ],
    );
  }
}

class _GenderSelector extends StatelessWidget {
  const _GenderSelector({
    required this.value,
    required this.onChanged,
    required this.enabled,
  });

  final String? value;
  final ValueChanged<String?> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(
            left: AppSpacing.xs,
            bottom: AppSpacing.sm,
          ),
          child: Text(
            'Tu género',
            style: theme.textTheme.labelMedium?.copyWith(
              color: context.palette.textPrimary,
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: context.palette.surface,
            borderRadius: BorderRadius.circular(AppRadius.field),
            border: Border.all(color: context.palette.outline, width: 1.2),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: context.palette.shadowSoft,
                blurRadius: 18,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Opacity(
            opacity: enabled ? 1.0 : 0.5,
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              hint: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md + AppSpacing.xs,
                ),
                child: Text(
                  'Selecciona',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: context.palette.textMuted,
                  ),
                ),
              ),
              items: const <DropdownMenuItem<String>>[
                DropdownMenuItem(
                  value: 'hombre',
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: AppSpacing.md + AppSpacing.xs,
                    ),
                    child: Text('Hombre'),
                  ),
                ),
                DropdownMenuItem(
                  value: 'mujer',
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: AppSpacing.md + AppSpacing.xs,
                    ),
                    child: Text('Mujer'),
                  ),
                ),
                DropdownMenuItem(
                  value: 'otro',
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: AppSpacing.md + AppSpacing.xs,
                    ),
                    child: Text('Otro'),
                  ),
                ),
              ],
              onChanged: enabled ? onChanged : null,
              underline: const SizedBox(),
              icon: Padding(
                padding: EdgeInsets.only(right: AppSpacing.md),
                child: Icon(
                  Icons.expand_more_rounded,
                  color: context.palette.iconSoft,
                ),
              ),
              style: theme.textTheme.bodyLarge?.copyWith(
                color: context.palette.textPrimary,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TermsCheckbox extends StatelessWidget {
  const _TermsCheckbox({
    required this.value,
    required this.enabled,
    required this.onChanged,
    required this.onRead,
  });

  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  /// Abre los Términos de Uso a pantalla completa.
  final VoidCallback onRead;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // El `Semantics` envuelve solo la casilla: si abarcase también el
        // enlace de abajo, el lector de pantalla anunciaría un único control
        // y no habría forma de llegar a los términos.
        Semantics(
          checked: value,
          enabled: enabled,
          label: 'Acepto los Términos de Uso y la Política de Privacidad',
          child: ExcludeSemantics(
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.field),
              onTap: enabled ? () => onChanged(!value) : null,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    SizedBox.square(
                      dimension: 24,
                      child: Checkbox(
                        value: value,
                        onChanged: enabled
                            ? (bool? next) => onChanged(next ?? false)
                            : null,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm + AppSpacing.xs),
                    Expanded(
                      child: Text(
                        'Acepto los Términos de Uso y la Política de Privacidad.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        TextButton(
          onPressed: enabled ? onRead : null,
          child: Text(
            'Leer términos de uso',
            style: theme.textTheme.labelMedium?.copyWith(
              color: context.palette.brandStrong,
              fontWeight: FontWeight.w600,
              decoration: TextDecoration.underline,
            ),
          ),
        ),
      ],
    );
  }
}
