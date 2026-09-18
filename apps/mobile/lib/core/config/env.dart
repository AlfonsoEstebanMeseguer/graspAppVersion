import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Configuración de entorno de la app móvil.
///
/// Solo entran aquí valores que **pueden viajar en el binario del cliente**:
/// la URL del proyecto y la `anon key` de Supabase (pública por diseño, acotada
/// por RLS). La `service_role key` no se lee nunca desde el cliente — vive solo
/// en backend (Sección 10 del documento maestro), y `assertNoServiceRoleKey`
/// existe para que un despiste al copiar/pegar falle de forma ruidosa en
/// desarrollo en vez de acabar publicado en una store.
///
/// Los valores se resuelven en este orden:
/// 1. `--dart-define` (lo que usa CI, que no lleva fichero `.env`).
/// 2. `apps/mobile/.env` cargado por `flutter_dotenv` (desarrollo local).
abstract final class Env {
  const Env._();

  static const String _dartDefineSupabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
  );
  static const String _dartDefineSupabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
  );

  /// Carga `.env` si existe. No falla si no está: en CI los valores llegan por
  /// `--dart-define` y no hay fichero que leer.
  static Future<void> load() async {
    try {
      await dotenv.load(isOptional: true);
    } on Object {
      // Un `.env` ausente o ilegible no debe impedir arrancar: la validación
      // real la hace `assertConfigured`, con un mensaje mucho más útil.
    }
  }

  static String get supabaseUrl =>
      _resolve('SUPABASE_URL', _dartDefineSupabaseUrl);

  static String get supabaseAnonKey =>
      _resolve('SUPABASE_ANON_KEY', _dartDefineSupabaseAnonKey);

  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  /// Falla temprano y con un mensaje accionable si falta configuración.
  static void assertConfigured() {
    if (!isConfigured) {
      throw StateError(
        'Falta configuración de Supabase.\n'
        'Copia apps/mobile/.env.example a apps/mobile/.env y rellena '
        'SUPABASE_URL y SUPABASE_ANON_KEY (los tienes en el .env de la raíz '
        'del repo), o pásalos con --dart-define.',
      );
    }
    assertNoServiceRoleKey(supabaseAnonKey);
    assertIsApiUrl(supabaseUrl);
  }

  /// Barrera de seguridad: la clave secreta nunca puede acabar embebida en la
  /// app (Sección 10 del documento maestro).
  ///
  /// Cubre los dos formatos que convivien hoy en Supabase: la clave nueva
  /// (`sb_secret_…`) y la antigua `service_role`, que es un JWT con
  /// `"role": "service_role"` en su payload.
  static void assertNoServiceRoleKey(String key) {
    final bool isNewSecretKey = key.startsWith('sb_secret_');
    if (isNewSecretKey || _roleClaimOf(key) == 'service_role') {
      throw StateError(
        'SUPABASE_ANON_KEY contiene una clave secreta (service_role). Esa '
        'clave salta RLS y NUNCA puede viajar en el cliente Flutter: úsala '
        'solo en Edge Functions. Sustitúyela por la clave publicable '
        '(sb_publishable_…).',
      );
    }
  }

  /// La URL debe ser la del **API** del proyecto
  /// (`https://<ref>.supabase.co`), no la del panel de control. Confundirlas es
  /// un error fácil de cometer al copiar del dashboard y produce fallos de red
  /// opacos en tiempo de ejecución en vez de un error claro al arrancar.
  static void assertIsApiUrl(String url) {
    if (url.contains('/dashboard/') || url.contains('supabase.com')) {
      throw StateError(
        'SUPABASE_URL apunta al panel de Supabase, no al API del proyecto. '
        'Debe tener la forma https://<project-ref>.supabase.co — lo encuentras '
        'en Project Settings → Data API.',
      );
    }
  }

  static String? _roleClaimOf(String jwt) {
    final List<String> parts = jwt.split('.');
    if (parts.length != 3) return null;
    try {
      final String payload = utf8.decode(
        base64Url.decode(base64Url.normalize(parts[1])),
      );
      final Object? decoded = jsonDecode(payload);
      if (decoded is Map<String, dynamic>) return decoded['role'] as String?;
    } on Object {
      // No es un JWT legible; no podemos afirmar nada sobre él.
    }
    return null;
  }

  static String _resolve(String key, String fromDartDefine) {
    if (fromDartDefine.isNotEmpty) return fromDartDefine;
    return dotenv.isInitialized ? (dotenv.env[key] ?? '') : '';
  }
}
