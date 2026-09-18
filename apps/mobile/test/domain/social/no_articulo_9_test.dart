import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guardián de los ADR 0020 y 0021 sobre la capa social.
///
/// ## Por qué este test lee el código fuente en vez de construir objetos
///
/// Lo que hay que impedir es que **aparezca un campo**, no que un campo dé un valor malo. Dart no
/// tiene reflexión en Flutter, así que no hay forma de preguntarle a una clase qué campos tiene en
/// tiempo de ejecución. La alternativa —un test por modelo comprobando su JSON— no cubre el caso
/// que importa: alguien **añade** `categorySlug` a `ConnectCandidate` y ningún test existente lo
/// nota, porque ninguno sabía que ese campo podía existir.
///
/// Leer el fuente sí lo nota, y se pone rojo en el commit que lo introduce.
///
/// **Se escanea solo el código, no los comentarios**: esta capa está llena de documentación que
/// explica *por qué* no hay categorías ni confirmación de lectura, y esas palabras tienen que poder
/// escribirse.
void main() {
  const List<String> directorios = <String>[
    'lib/domain/social',
    'lib/data/social',
    // La pantalla Conectar entra en el escaneo desde la Tarea 21: es **la única** que pinta datos
    // de otra persona sacados del scoring del §7, así que es por donde una categoría volvería.
    'lib/features/connect',
    // Y el perfil desde la Tarea 24, por el perfil AJENO (`public_profile_screen.dart`): es la
    // otra pantalla que pinta datos de otra persona, y la que más campos suyos enseña. Entra el
    // directorio entero y no solo esa pantalla a propósito — el perfil PROPIO puede enseñar las
    // categorías de uno mismo sin problema, pero ninguna de las dos pantallas comparte modelo, así
    // que un campo de categoría aquí solo puede haber llegado por la vía ajena.
    'lib/features/profile',
  ];

  /// Quita comentarios de línea (`//`, `///`) y de bloque, para escanear solo código.
  String soloCodigo(String source) {
    final String sinBloques = source.replaceAll(
      RegExp(r'/\*.*?\*/', dotAll: true),
      '',
    );
    return sinBloques
        .split('\n')
        .where((String line) => !line.trimLeft().startsWith('//'))
        .join('\n');
  }

  List<File> ficheros() => directorios
      .expand(
        (String dir) => Directory(dir)
            .listSync(recursive: true)
            .whereType<File>()
            .where((File f) => f.path.endsWith('.dart')),
      )
      .toList();

  test('hay ficheros que escanear (si no, este test sería vacuo)', () {
    // Sin esto, mover o renombrar el directorio dejaría el test en verde para siempre sin mirar
    // nada — el fallo que `CLAUDE.md` recuerda como «un test de regresión tiene que poder fallar».
    expect(ficheros().length, greaterThanOrEqualTo(10));
  });

  group('ADR 0021 — la mensajería de Grasp no tiene confirmación de lectura', () {
    // `RN-31`: no hay `direct_messages.read_at`, ni columna, ni campo, ni derivado. Lo único que
    // existe es el `unread_count` PROPIO, que vive en `conversation_states`.
    final List<RegExp> prohibidos = <RegExp>[
      RegExp(r'\bread_?At\b', caseSensitive: false),
      RegExp(r'\bseen_?At\b', caseSensitive: false),
      RegExp(r'\breadReceipt', caseSensitive: false),
      RegExp(r'\bisRead\b', caseSensitive: false),
      RegExp(r'\bdeliveredAt\b', caseSensitive: false),
    ];

    test('ningún fichero de la capa social nombra una marca de lectura', () {
      for (final File file in ficheros()) {
        final String code = soloCodigo(file.readAsStringSync());
        for (final RegExp prohibido in prohibidos) {
          expect(
            code,
            isNot(contains(prohibido)),
            reason:
                '${file.path} usa "${prohibido.pattern}". El ADR 0021 y RN-31 prohíben la '
                'confirmación de lectura en Grasp: no hay columna que lo alimente y el campo '
                'solo puede acabar mintiendo o filtrando.',
          );
        }
      }
    });
  });

  group('ADR 0020 — ni un dato del Art. 9 RGPD de OTRA persona', () {
    // El scoring de Conectar lee `user_experiences`, `profiles_private.primary_category_id` /
    // `secondary_categories` y `onboarding_responses.responses` con service_role DENTRO de
    // `connect-feed`, y devuelve UN NÚMERO. Ni un slug, ni un id, ni el desglose por eje — el
    // desglose diría QUÉ eje coincidió, que es la categoría dicha de otra forma.
    // OJO CON EL `\b` FINAL: la primera versión de esta lista era
    // `\bcategor(y|ies|ia|Slug|Id)\b`, y **dejaba pasar `categorySlug`** — tras `category` viene
    // una `S`, que es carácter de palabra, así que la frontera no casaba. El test pasaba en verde
    // y no cubría el caso más probable de todos. Se descubrió mutando el modelo para añadir ese
    // campo exacto; sin esa comprobación habría quedado como un guardián decorativo.
    //
    // Por eso ahora se busca el PREFIJO y se deja el sufijo libre.
    final List<RegExp> prohibidos = <RegExp>[
      RegExp(r'categor', caseSensitive: false),
      RegExp(r'experienceCase', caseSensitive: false),
      RegExp(r'experience_case', caseSensitive: false),
      RegExp(r'user_experiences', caseSensitive: false),
      RegExp(r'onboarding_responses', caseSensitive: false),
      RegExp(r'diagnos', caseSensitive: false),
      // `suffered` NO entra en esta lista: es el nombre de uno de los chips del §6.3, o sea una
      // elección de quien mira que viaja HACIA el backend. Lo que el ADR 0020 prohíbe es que
      // vuelva el dato de OTRA persona, no que se pueda filtrar.
      RegExp(r'\bmatchBreakdown', caseSensitive: false),
      RegExp(r'\bmatchScore', caseSensitive: false),
    ];

    test('ningún modelo social lleva una categoría de salud mental', () {
      for (final File file in ficheros()) {
        final String code = soloCodigo(file.readAsStringSync());
        for (final RegExp prohibido in prohibidos) {
          expect(
            code,
            isNot(contains(prohibido)),
            reason:
                '${file.path} usa "${prohibido.pattern}". Es dato del Art. 9 RGPD de otra '
                'persona y el ADR 0020 lo prohíbe en el cliente. Ni el desglose por eje: '
                'diría QUÉ eje coincidió, que es la categoría dicha de otra forma.',
          );
        }
      }
    });
  });

  group('RN-06 — el estado y el iniciador de una conversación no salen de la base', () {
    test('los modelos de mensajería no tienen `status` ni `initiator`', () {
      // `conversations` no tiene ni un `grant` para `authenticated`: lo que la pantalla necesita
      // viaja DERIVADO (`pending_acceptance`, `from_me`). Un campo `status` aquí solo puede
      // rellenarse desde algo que el backend se niega a emitir — o inventándolo.
      //
      // `FollowState` sí se llama status y es correcto: es el estado de un SEGUIMIENTO, público
      // por `user_follows`, no el de una conversación. Por eso el escaneo va por fichero.
      for (final String path in <String>[
        'lib/domain/social/conversation_summary.dart',
        'lib/domain/social/message.dart',
      ]) {
        final String code = soloCodigo(File(path).readAsStringSync());
        expect(
          code,
          isNot(contains(RegExp(r'\binitiator', caseSensitive: false))),
          reason: '$path nombra al iniciador de la conversación (RN-06).',
        );
        expect(
          code,
          isNot(contains(RegExp(r'\bstatus\b', caseSensitive: false))),
          reason:
              '$path nombra el `status` de la conversación. Una `ignored` tiene que verse '
              'igual que una `pending` para quien la inició (RN-06).',
        );
      }
    });
  });
}
