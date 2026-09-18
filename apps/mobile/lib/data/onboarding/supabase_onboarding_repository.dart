import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/onboarding/onboarding_answers.dart';
import '../../domain/onboarding/onboarding_failure.dart';
import '../../domain/onboarding/onboarding_repository.dart';

/// Implementación de [OnboardingRepository] sobre la Edge Function
/// `onboarding-complete`.
///
/// Contrato reescrito el 2026-08-09: el body es plano, en español, con slugs
/// — `{situation, experiences, profile, interests, discovery}` — en vez del
/// `{"answers": {...}}` anidado con ids en inglés que mandaba la versión
/// anterior de esta clase. El backend es la fuente de verdad del contrato
/// (ver `apps/backend/supabase/functions/onboarding-complete/index.ts`); si
/// vuelve a cambiar, este es el único fichero cliente que debería tocarse.
class SupabaseOnboardingRepository implements OnboardingRepository {
  SupabaseOnboardingRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<void> complete(OnboardingAnswers answers) async {
    try {
      final FunctionResponse response = await _client.functions.invoke(
        'onboarding-complete',
        body: <String, dynamic>{
          'situation': answers.situation,
          'experiences': answers.experiences,
          'profile': answers.profile,
          'interests': answers.interests,
          'discovery': answers.discovery,
        },
      );

      if (response.status < 200 || response.status >= 300) {
        throw const OnboardingFailure(
          'No se pudieron guardar tus respuestas. Inténtalo de nuevo.',
        );
      }
    } on OnboardingFailure {
      rethrow;
    } on FunctionException catch (error) {
      throw OnboardingFailure(
        _messageFrom(error) ??
            'No se pudieron guardar tus respuestas. Inténtalo de nuevo.',
      );
    } on TimeoutException {
      throw const OnboardingFailure('Sin conexión. Inténtalo de nuevo.');
    } on Object catch (error) {
      final String message = error.toString();
      final bool looksLikeNetwork =
          message.contains('SocketException') ||
          message.contains('ClientException') ||
          message.contains('Failed host lookup');
      throw OnboardingFailure(
        looksLikeNetwork
            ? 'Sin conexión. Inténtalo de nuevo.'
            : 'No se pudieron guardar tus respuestas. Inténtalo de nuevo.',
      );
    }
  }

  String? _messageFrom(FunctionException error) {
    final Object? details = error.details;
    if (details is Map && details['message'] is String) {
      return details['message'] as String;
    }
    return null;
  }
}
