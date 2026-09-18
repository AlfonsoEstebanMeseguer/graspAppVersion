import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grasp_mobile/data/supabase/supabase_providers.dart';
import 'package:grasp_mobile/domain/onboarding/onboarding_answers.dart';
import 'package:grasp_mobile/features/onboarding/application/onboarding_controller.dart';

import '../../../support/fake_onboarding_repositories.dart';

void main() {
  late FakeOnboardingCatalogsRepository fakeCatalogs;
  late FakeOnboardingRepository fakeRepository;
  late ProviderContainer container;

  setUp(() {
    fakeCatalogs = FakeOnboardingCatalogsRepository();
    fakeRepository = FakeOnboardingRepository();
    container = ProviderContainer(
      overrides: <Override>[
        onboardingCatalogsRepositoryProvider.overrideWithValue(fakeCatalogs),
        onboardingRepositoryProvider.overrideWithValue(fakeRepository),
      ],
    );
    addTearDown(container.dispose);
  });

  test('carga las 5 preguntas desde los catálogos, en el orden del contrato', () async {
    final OnboardingState state = await container.read(
      onboardingControllerProvider.future,
    );

    expect(state.questions.map((q) => q.key).toList(), <String>[
      'situation',
      'experiences',
      'profile',
      'interests',
      'discovery',
    ]);
    expect(state.questions[0].multiSelect, isFalse);
    expect(state.questions[1].multiSelect, isTrue); // experiences
    expect(state.questions[3].multiSelect, isTrue); // interests
    expect(state.currentIndex, 0);
  });

  test('pregunta de selección única sustituye la respuesta anterior', () async {
    await container.read(onboardingControllerProvider.future);
    final OnboardingController controller = container.read(
      onboardingControllerProvider.notifier,
    );

    controller.toggleOption('ansiedad-estres');
    controller.toggleOption('soledad');

    final OnboardingState state = container.read(onboardingControllerProvider).value!;
    expect(state.selectedFor('situation'), <String>{'soledad'});
  });

  test('pregunta multi-select acumula y permite deseleccionar', () async {
    await container.read(onboardingControllerProvider.future);
    final OnboardingController controller = container.read(
      onboardingControllerProvider.notifier,
    );

    // Avanza a la pregunta 2 ("experiences"): situation es obligatoria antes.
    controller.toggleOption('ansiedad-estres');
    await controller.next();

    controller.toggleOption('no-duermo-bien');
    controller.toggleOption('sin-gente-cerca');
    expect(
      container.read(onboardingControllerProvider).value!.selectedFor('experiences'),
      <String>{'no-duermo-bien', 'sin-gente-cerca'},
    );

    controller.toggleOption('no-duermo-bien');
    expect(
      container.read(onboardingControllerProvider).value!.selectedFor('experiences'),
      <String>{'sin-gente-cerca'},
    );
  });

  test('al completar la última pregunta envía el payload plano con slugs', () async {
    await container.read(onboardingControllerProvider.future);
    final OnboardingController controller = container.read(
      onboardingControllerProvider.notifier,
    );

    controller.toggleOption('ansiedad-estres');
    await controller.next(); // -> experiences
    controller.toggleOption('no-duermo-bien');
    await controller.next(); // -> profile
    controller.toggleOption('empatico-cercano');
    await controller.next(); // -> interests
    controller.toggleOption('soledad');
    await controller.next(); // -> discovery
    controller.toggleOption('redes-sociales');
    final bool completed = await controller.next(); // envía

    expect(completed, isTrue);
    expect(fakeRepository.completedCalls, hasLength(1));
    final OnboardingAnswers sent = fakeRepository.completedCalls.single;
    expect(sent.situation, 'ansiedad-estres');
    expect(sent.experiences, <String>['no-duermo-bien']);
    expect(sent.profile, 'empatico-cercano');
    expect(sent.interests, <String>['soledad']);
    expect(sent.discovery, 'redes-sociales');
  });

  test('back() no hace nada en la primera pregunta', () async {
    await container.read(onboardingControllerProvider.future);
    final OnboardingController controller = container.read(
      onboardingControllerProvider.notifier,
    );

    controller.back();
    expect(container.read(onboardingControllerProvider).value!.currentIndex, 0);
  });
}