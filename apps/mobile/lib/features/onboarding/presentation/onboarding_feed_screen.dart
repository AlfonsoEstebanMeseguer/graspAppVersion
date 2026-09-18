import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theming/grasp_palette.dart';
import '../../../core/theming/app_motion.dart';
import '../../../core/theming/app_theme.dart';
import '../../../core/ui/brand_mark.dart';
import '../../../core/ui/grasp_backdrop.dart';
import '../../../core/ui/grasp_buttons.dart';
import '../../../data/supabase/supabase_providers.dart';
import '../../../domain/onboarding/onboarding_question.dart';
import '../application/onboarding_controller.dart';
import 'widgets/onboarding_option_card.dart';
import 'widgets/onboarding_progress_track.dart';

/// Las 5 preguntas de bienvenida — `02-onboarding-questions.jpeg`.
///
/// Se muestra tras el registro (o al reeditar el feed desde Perfil). Carga
/// primero los catálogos del backend (`GET onboarding-catalogs`) y luego
/// mantiene las respuestas en memoria hasta que la última se envía de golpe a
/// `onboarding-complete`; al terminar navega a Home.
class OnboardingFeedScreen extends ConsumerWidget {
  const OnboardingFeedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<OnboardingState> stateAsync = ref.watch(
      onboardingControllerProvider,
    );

    ref.listen<AsyncValue<OnboardingState>>(onboardingControllerProvider, (
      AsyncValue<OnboardingState>? previous,
      AsyncValue<OnboardingState> next,
    ) {
      final String? nextError = next.valueOrNull?.errorMessage;
      if (nextError != null && nextError != previous?.valueOrNull?.errorMessage) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(nextError)));
      }
    });

    return Scaffold(
      body: GraspBackdrop(
        sceneHeightFactor: 0.22,
        sceneOpacity: 0.3,
        child: SafeArea(
          child: stateAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (Object error, StackTrace _) => _ErrorView(
              onRetry: () => ref.invalidate(onboardingControllerProvider),
            ),
            data: (OnboardingState state) => _OnboardingBody(state: state),
          ),
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.gutter),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              'No se pudieron cargar las preguntas del cuestionario.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.md),
            OutlinedButton(onPressed: onRetry, child: const Text('Reintentar')),
          ],
        ),
      ),
    );
  }
}

class _OnboardingBody extends ConsumerWidget {
  const _OnboardingBody({required this.state});

  final OnboardingState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final OnboardingController controller = ref.read(
      onboardingControllerProvider.notifier,
    );
    final OnboardingQuestion question = state.currentQuestion;

    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          child: Row(
            children: <Widget>[
              IconButton(
                onPressed: () {
                  if (state.isFirstQuestion) {
                    context.pop();
                  } else {
                    controller.back();
                  }
                },
                icon: const Icon(Icons.arrow_back_rounded),
                color: context.palette.textPrimary,
                tooltip: 'Volver',
              ),
              const Expanded(child: SizedBox.shrink()),
            ],
          ),
        ),
        const BrandMark(size: 40),
        const SizedBox(height: AppSpacing.sm),
        Text('Bienvenido/a', style: theme.textTheme.headlineMedium),
        const SizedBox(height: AppSpacing.md),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
          child: OnboardingProgressTrack(
            total: state.questions.length,
            currentIndex: state.currentIndex,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Expanded(
          child: AnimatedSwitcher(
            duration: AppMotion.medium,
            switchInCurve: AppMotion.enter,
            switchOutCurve: AppMotion.exit,
            transitionBuilder: (Widget child, Animation<double> animation) =>
                FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0.04, 0),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                ),
            child: SingleChildScrollView(
              key: ValueKey<String>(question.key),
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.gutter,
                0,
                AppSpacing.gutter,
                AppSpacing.lg,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(question.title, style: theme.textTheme.headlineMedium),
                  const SizedBox(height: AppSpacing.xs),
                  Text(question.subtitle, style: theme.textTheme.bodyMedium),
                  const SizedBox(height: AppSpacing.lg),
                  GridView.count(
                    crossAxisCount: 3,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: AppSpacing.sm,
                    crossAxisSpacing: AppSpacing.sm,
                    childAspectRatio: OnboardingOptionCard.gridAspectRatio,
                    children: <Widget>[
                      for (final OnboardingOption option in question.options)
                        OnboardingOptionCard(
                          option: option,
                          selected: controller.isSelected(option.slug),
                          onTap: () => controller.toggleOption(option.slug),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.gutter,
            0,
            AppSpacing.gutter,
            AppSpacing.lg,
          ),
          child: GraspPrimaryButton(
            label: state.isLastQuestion ? 'Empezar' : 'Continuar',
            isLoading: state.isSubmitting,
            onPressed: state.canContinue
                ? () async {
                    final bool completed = await controller.next();
                    if (completed && context.mounted) {
                      ref.invalidate(hasCompletedOnboardingProvider);
                      context.go(AppRoute.messages);
                    }
                  }
                : null,
          ),
        ),
      ],
    );
  }
}