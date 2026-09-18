import 'package:grasp_mobile/domain/onboarding/onboarding_answers.dart';
import 'package:grasp_mobile/domain/onboarding/onboarding_catalogs.dart';
import 'package:grasp_mobile/domain/onboarding/onboarding_catalogs_repository.dart';
import 'package:grasp_mobile/domain/onboarding/onboarding_failure.dart';
import 'package:grasp_mobile/domain/onboarding/onboarding_repository.dart';

/// Catálogos mínimos pero realistas (mismos slugs que sirve
/// `onboarding-catalogs` de verdad) para no acoplar los tests a la red.
OnboardingCatalogs fakeOnboardingCatalogs() => const OnboardingCatalogs(
  categories: <CatalogOption>[
    CatalogOption(slug: 'ansiedad-estres', name: 'Ansiedad y estrés cotidiano'),
    CatalogOption(slug: 'soledad', name: 'Soledad'),
  ],
  experienceCases: <ExperienceCaseOption>[
    ExperienceCaseOption(
      slug: 'no-duermo-bien',
      name: 'Llevo semanas durmiendo mal',
      categorySlug: 'ansiedad-estres',
    ),
    ExperienceCaseOption(
      slug: 'sin-gente-cerca',
      name: 'Siento que no tengo a nadie cerca',
      categorySlug: 'soledad',
    ),
  ],
  listenerProfiles: <CatalogOption>[
    CatalogOption(slug: 'empatico-cercano', name: 'Empático y cercano'),
    CatalogOption(slug: 'directo-practico', name: 'Directo y práctico'),
  ],
  discoverySources: <CatalogOption>[
    CatalogOption(slug: 'redes-sociales', name: 'Redes sociales'),
    CatalogOption(slug: 'otro', name: 'Otro'),
  ],
);

class FakeOnboardingCatalogsRepository implements OnboardingCatalogsRepository {
  OnboardingFailure? nextFailure;

  @override
  Future<OnboardingCatalogs> getCatalogs() async {
    final OnboardingFailure? failure = nextFailure;
    if (failure != null) {
      nextFailure = null;
      throw failure;
    }
    return fakeOnboardingCatalogs();
  }
}

class FakeOnboardingRepository implements OnboardingRepository {
  final List<OnboardingAnswers> completedCalls = <OnboardingAnswers>[];
  OnboardingFailure? nextFailure;

  @override
  Future<void> complete(OnboardingAnswers answers) async {
    final OnboardingFailure? failure = nextFailure;
    if (failure != null) {
      nextFailure = null;
      throw failure;
    }
    completedCalls.add(answers);
  }
}