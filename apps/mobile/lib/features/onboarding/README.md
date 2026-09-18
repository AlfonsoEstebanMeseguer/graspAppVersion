# features/onboarding

Cuestionario de alta (5 preguntas: situación, experiencias vividas, perfil de oyente preferido,
temas de interés, cómo nos descubrió) que alimenta `match-feed`. Boceto: `pictures/screens/02-onboarding-questions.jpeg`.

Las opciones de cada pregunta **no están hardcodeadas**: se cargan en tiempo de ejecución desde
`GET onboarding-catalogs` (`domain/onboarding/onboarding_catalogs_repository.dart`) y se resuelven
a las 5 preguntas con `OnboardingQuestions.build(catalogs)`
(`domain/onboarding/onboarding_question.dart`). El envío usa el contrato plano de
`onboarding-complete` (2026-08-09): `{situation, experiences, profile, interests, discovery}`, todo
slugs de catálogo — ver `domain/onboarding/onboarding_answers.dart`.

El router (`core/router/app_router.dart`) redirige aquí automáticamente tras el login si
`hasCompletedOnboardingProvider` (existencia de fila en `onboarding_responses`) es `false`. La
pantalla también se reabre en modo "editar" desde Perfil (botón "Revisar / editar mi feed" de
`ProfileEditSheet`), vía `Navigator.push` directo — esa ruta no pasa por el redirect del router.
