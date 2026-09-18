import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/supabase/supabase_providers.dart';
import '../../../domain/onboarding/onboarding_answers.dart';
import '../../../domain/onboarding/onboarding_catalogs_repository.dart';
import '../../../domain/onboarding/onboarding_failure.dart';
import '../../../domain/onboarding/onboarding_question.dart';
import '../../../domain/onboarding/onboarding_repository.dart';

@immutable
class OnboardingState {
  const OnboardingState({
    required this.questions,
    this.currentIndex = 0,
    this.selections = const <String, Set<String>>{},
    this.isSubmitting = false,
    this.errorMessage,
  });

  /// Las 5 preguntas ya resueltas contra los catálogos del backend
  /// (`OnboardingQuestions.build`). Inmutable durante toda la sesión de
  /// onboarding: los catálogos no cambian mientras se responde.
  final List<OnboardingQuestion> questions;

  final int currentIndex;

  /// `questionKey` -> slugs de opción elegidos.
  final Map<String, Set<String>> selections;
  final bool isSubmitting;
  final String? errorMessage;

  OnboardingQuestion get currentQuestion => questions[currentIndex];

  bool get isFirstQuestion => currentIndex == 0;
  bool get isLastQuestion => currentIndex == questions.length - 1;

  double get progress => (currentIndex + 1) / questions.length;

  Set<String> selectedFor(String questionKey) =>
      selections[questionKey] ?? const <String>{};

  bool get canContinue => selectedFor(currentQuestion.key).isNotEmpty;

  OnboardingState copyWith({
    int? currentIndex,
    Map<String, Set<String>>? selections,
    bool? isSubmitting,
    String? errorMessage,
    bool clearError = false,
  }) => OnboardingState(
    questions: questions,
    currentIndex: currentIndex ?? this.currentIndex,
    selections: selections ?? this.selections,
    isSubmitting: isSubmitting ?? this.isSubmitting,
    errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
  );
}

/// Orquesta el flujo de las 5 preguntas de `02-onboarding-questions.jpeg`.
///
/// `build()` carga primero los catálogos (`GET onboarding-catalogs`) — sin
/// ellos no hay opciones que pintar — y luego mantiene las respuestas en
/// memoria mientras el usuario avanza; solo se envían al backend al completar
/// la última pregunta, porque `onboarding-complete` valida y persiste el
/// conjunto entero de una vez.
class OnboardingController extends AutoDisposeAsyncNotifier<OnboardingState> {
  @override
  Future<OnboardingState> build() async {
    final OnboardingCatalogsRepository catalogsRepository = ref.read(
      onboardingCatalogsRepositoryProvider,
    );
    final questions = OnboardingQuestions.build(
      await catalogsRepository.getCatalogs(),
    );
    return OnboardingState(questions: questions);
  }

  OnboardingRepository get _repository => ref.read(onboardingRepositoryProvider);

  void toggleOption(String optionSlug) {
    final OnboardingState? current = state.valueOrNull;
    if (current == null) return;

    final OnboardingQuestion question = current.currentQuestion;
    final Set<String> selected = Set<String>.from(
      current.selectedFor(question.key),
    );

    if (question.multiSelect) {
      if (!selected.remove(optionSlug)) selected.add(optionSlug);
    } else {
      selected
        ..clear()
        ..add(optionSlug);
    }

    state = AsyncData<OnboardingState>(
      current.copyWith(
        selections: <String, Set<String>>{
          ...current.selections,
          question.key: selected,
        },
        clearError: true,
      ),
    );
  }

  bool isSelected(String optionSlug) {
    final OnboardingState? current = state.valueOrNull;
    if (current == null) return false;
    return current.selectedFor(current.currentQuestion.key).contains(optionSlug);
  }

  /// Avanza a la siguiente pregunta, o envía las respuestas si es la última.
  ///
  /// Devuelve `true` si el onboarding se completó con éxito (el llamador debe
  /// navegar a Home). `false` en cualquier otro caso, incluido "avanzó de
  /// pregunta pero aún no ha terminado".
  Future<bool> next() async {
    final OnboardingState? current = state.valueOrNull;
    if (current == null || !current.canContinue || current.isSubmitting) {
      return false;
    }

    if (!current.isLastQuestion) {
      state = AsyncData<OnboardingState>(
        current.copyWith(currentIndex: current.currentIndex + 1, clearError: true),
      );
      return false;
    }

    state = AsyncData<OnboardingState>(
      current.copyWith(isSubmitting: true, clearError: true),
    );
    try {
      await _repository.complete(
        OnboardingAnswers(
          situation: current.selectedFor('situation').first,
          experiences: current.selectedFor('experiences').toList(),
          profile: current.selectedFor('profile').first,
          interests: current.selectedFor('interests').toList(),
          discovery: current.selectedFor('discovery').first,
        ),
      );
      state = AsyncData<OnboardingState>(current.copyWith(isSubmitting: false));
      return true;
    } on OnboardingFailure catch (failure) {
      state = AsyncData<OnboardingState>(
        current.copyWith(isSubmitting: false, errorMessage: failure.message),
      );
      return false;
    }
  }

  /// Retrocede una pregunta. En la primera, no hace nada — la pantalla decide
  /// si `context.pop()` cuando `state.isFirstQuestion`.
  void back() {
    final OnboardingState? current = state.valueOrNull;
    if (current == null || current.isFirstQuestion) return;
    state = AsyncData<OnboardingState>(
      current.copyWith(currentIndex: current.currentIndex - 1, clearError: true),
    );
  }
}

final AutoDisposeAsyncNotifierProvider<OnboardingController, OnboardingState>
onboardingControllerProvider =
    AsyncNotifierProvider.autoDispose<OnboardingController, OnboardingState>(
      OnboardingController.new,
    );