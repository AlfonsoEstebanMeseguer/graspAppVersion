import 'dart:async';
import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/onboarding/onboarding_catalogs.dart';
import '../../domain/onboarding/onboarding_catalogs_repository.dart';
import '../../domain/onboarding/onboarding_failure.dart';

/// Implementación de [OnboardingCatalogsRepository] sobre la Edge Function
/// `GET onboarding-catalogs`.
///
/// No requiere sesión (la función se sirve con `service_role` y no expone
/// nada sensible, ver el comentario de esa función), pero se invoca con el
/// cliente normal de Supabase igualmente: si hay sesión, el SDK manda el JWT,
/// y si no la hay, manda la `anon key` — ambas rutas responden 200.
class SupabaseOnboardingCatalogsRepository
    implements OnboardingCatalogsRepository {
  SupabaseOnboardingCatalogsRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<OnboardingCatalogs> getCatalogs() async {
    try {
      final FunctionResponse response = await _client.functions.invoke(
        'onboarding-catalogs',
        method: HttpMethod.get,
      );

      if (response.status < 200 || response.status >= 300) {
        throw const OnboardingFailure(
          'No se pudieron cargar las opciones del cuestionario.',
        );
      }

      final Map<String, dynamic> body = _asMap(response.data);
      return OnboardingCatalogs(
        categories: _catalogOptions(body['categories']),
        experienceCases: _experienceCaseOptions(body['experience_cases']),
        listenerProfiles: _catalogOptions(body['listener_profiles']),
        discoverySources: _catalogOptions(body['discovery_sources']),
      );
    } on OnboardingFailure {
      rethrow;
    } on FunctionException catch (error) {
      throw OnboardingFailure(
        _messageFrom(error) ??
            'No se pudieron cargar las opciones del cuestionario.',
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
            : 'No se pudieron cargar las opciones del cuestionario.',
      );
    }
  }

  Map<String, dynamic> _asMap(Object? data) {
    if (data is Map<String, dynamic>) return data;
    if (data is String) return jsonDecode(data) as Map<String, dynamic>;
    throw const OnboardingFailure(
      'No se pudieron cargar las opciones del cuestionario.',
    );
  }

  List<CatalogOption> _catalogOptions(Object? raw) {
    if (raw is! List) return const <CatalogOption>[];
    return <CatalogOption>[
      for (final Object? item in raw)
        if (item is Map)
          CatalogOption(
            slug: item['slug'] as String,
            name: item['name'] as String,
          ),
    ];
  }

  List<ExperienceCaseOption> _experienceCaseOptions(Object? raw) {
    if (raw is! List) return const <ExperienceCaseOption>[];
    return <ExperienceCaseOption>[
      for (final Object? item in raw)
        if (item is Map)
          ExperienceCaseOption(
            slug: item['slug'] as String,
            name: item['name'] as String,
            categorySlug: item['category_slug'] as String?,
          ),
    ];
  }

  String? _messageFrom(FunctionException error) {
    final Object? details = error.details;
    if (details is Map && details['message'] is String) {
      return details['message'] as String;
    }
    return null;
  }
}
