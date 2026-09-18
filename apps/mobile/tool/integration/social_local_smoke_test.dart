import 'package:flutter_test/flutter_test.dart';
import 'package:grasp_mobile/data/social/supabase_activity_repository.dart';
import 'package:grasp_mobile/data/social/supabase_connect_repository.dart';
import 'package:grasp_mobile/data/social/supabase_follow_repository.dart';
import 'package:grasp_mobile/data/social/supabase_messaging_repository.dart';
import 'package:grasp_mobile/data/social/supabase_moderation_repository.dart';
import 'package:grasp_mobile/domain/social/connect_candidate.dart';
import 'package:grasp_mobile/domain/social/conversation_summary.dart';
import 'package:grasp_mobile/domain/social/follow_edge.dart';
import 'package:grasp_mobile/domain/social/message.dart';
import 'package:grasp_mobile/domain/social/message_input_state.dart';
import 'package:grasp_mobile/domain/social/messaging_repository.dart';
import 'package:grasp_mobile/domain/social/social_failure.dart';
import 'package:grasp_mobile/domain/social/tag_lookup_result.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// **Humo de integración de la capa social contra el stack LOCAL.**
///
/// ## Por qué existe, si ya hay 66 tests unitarios de esta capa
///
/// Los unitarios prueban el parseo y las reglas. **No pueden probar que la llamada exista**: que el
/// nombre de la función sea el bueno, que el verbo sea POST y no GET, que los parámetros se llamen
/// como el handler espera, ni —el que más duele— que el alias de la clave ajena del `select`
/// incrustado de PostgREST sea el correcto. `user_follows` tiene **dos** claves ajenas hacia
/// `profiles`, así que sin nombrarla PostgREST devuelve `PGRST201` y la lista sale vacía o revienta.
/// Ese fallo pasa `flutter analyze`, pasa `flutter test` y solo aparece con la pantalla delante.
///
/// ## No corre con `flutter test`
///
/// Está fuera de `test/` a propósito: necesita Docker, el stack levantado y crea usuarios de
/// verdad. Se lanza a mano desde `apps/mobile`:
///
/// ```sh
/// supabase --workdir ../backend status -o env | grep '^ANON_KEY=' > /tmp/anon.env
/// source /tmp/anon.env
/// flutter test tool/integration/social_local_smoke_test.dart \
///   --dart-define=SUPABASE_URL=http://127.0.0.1:54321 \
///   --dart-define=SUPABASE_ANON_KEY="$ANON_KEY"
/// ```
///
/// Los usuarios que crea se van con el siguiente `supabase db reset`.
const String _url = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: 'http://127.0.0.1:54321',
);
const String _anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

/// Una persona de prueba con su propio cliente autenticado.
class _Persona {
  _Persona(this.nombre, this.client, this.userId);

  final String nombre;
  final SupabaseClient client;
  final String userId;
}

Future<_Persona> _crear(String nombre, String sufijo) async {
  final SupabaseClient client = SupabaseClient(
    _url,
    _anonKey,
    // La app usa PKCE, que exige un almacenamiento asíncrono de plataforma (el que monta
    // `Supabase.initialize`). Aquí no hay plugins de Flutter, así que se usa el flujo implícito:
    // cambia cómo se OBTIENE el token, no lo que el token permite hacer, que es lo que este humo
    // ejercita.
    authOptions: const AuthClientOptions(authFlowType: AuthFlowType.implicit),
  );
  final AuthResponse auth = await client.auth.signUp(
    email: '$nombre.$sufijo@grasp.test',
    password: 'Contrasena-de-prueba-1',
    // `display_name` es OBLIGATORIO desde el ADR 0018: sin él, `handle_new_user` lanza
    // `check_violation` y el alta devuelve un 500.
    data: <String, dynamic>{'display_name': nombre},
  );
  final User? user = auth.user;
  if (user == null) throw StateError('No se pudo crear $nombre');
  return _Persona(nombre, client, user.id);
}

void main() {
  if (_anonKey.isEmpty) {
    // Falla, NO se salta: un humo que se salta solo cuando le falta la configuración es
    // exactamente el test que pasa siempre sin comprobar nada.
    test('falta --dart-define=SUPABASE_ANON_KEY', () {
      fail(
        'Este humo necesita la ANON_KEY del stack local. Ver la cabecera del fichero.',
      );
    });
    return;
  }

  late _Persona ana;
  late _Persona beto;
  late _Persona carla;

  setUpAll(() async {
    final String sufijo = DateTime.now().millisecondsSinceEpoch.toString();
    ana = await _crear('ana', sufijo);
    beto = await _crear('beto', sufijo);
    carla = await _crear('carla', sufijo);
  });

  test('el tag se acuña solo al crear el perfil (§13)', () async {
    final Map<String, dynamic> row = await ana.client
        .from('profiles')
        .select('tag, display_name')
        .eq('user_id', ana.userId)
        .single();
    expect(row['tag'], matches(RegExp(r'^[a-z0-9]{1,12}#[0-9A-HJKMNP-TV-Z]{8}$')));
    expect(row['display_name'], 'ana');
  });

  test('connect-tag-lookup encuentra por tag exacto y da el follow_state', () async {
    final Map<String, dynamic> row = await beto.client
        .from('profiles')
        .select('tag')
        .eq('user_id', beto.userId)
        .single();

    final TagLookupResult? found = await SupabaseConnectRepository(
      ana.client,
    ).lookupTag(row['tag'] as String);

    expect(found, isNotNull);
    expect(found!.userId, beto.userId);
    expect(found.displayName, 'beto');
    expect(found.followState, FollowState.none);
  });

  test('un tag inexistente devuelve null, no una excepción', () async {
    expect(
      await SupabaseConnectRepository(ana.client).lookupTag('nadie#ZZZZZZZZ'),
      isNull,
    );
  });

  test('buscar el tag propio se distingue y da ownTag', () async {
    final Map<String, dynamic> row = await ana.client
        .from('profiles')
        .select('tag')
        .eq('user_id', ana.userId)
        .single();

    await expectLater(
      SupabaseConnectRepository(ana.client).lookupTag(row['tag'] as String),
      throwsA(
        isA<SocialFailure>().having(
          (SocialFailure f) => f.kind,
          'kind',
          SocialFailureKind.ownTag,
        ),
      ),
    );
  });

  test('follow-toggle: request → accept, y la lista incrustada se lee', () async {
    final SupabaseFollowRepository anaFollows = SupabaseFollowRepository(
      ana.client,
    );
    final SupabaseFollowRepository betoFollows = SupabaseFollowRepository(
      beto.client,
    );

    expect(
      (await anaFollows.toggle(FollowAction.request, beto.userId)).status,
      FollowState.pending,
    );

    // La solicitud le aparece a BETO, no a Ana.
    final List<FollowRequest> pendientes = await betoFollows.pendingRequests();
    expect(pendientes.map((FollowRequest r) => r.profile.userId), <String>[
      ana.userId,
    ]);
    expect(pendientes.single.profile.displayName, 'ana');

    // `follow-toggle` devuelve el literal `accepted`; `connect-tag-lookup`, `following`. Los dos
    // tienen que resolver al mismo estado — ver el alias de `FollowState.fromWire`, que este humo
    // es quien lo descubrió.
    expect(
      (await betoFollows.toggle(FollowAction.accept, ana.userId)).status,
      FollowState.following,
    );

    // AQUÍ ES DONDE SE COMPRUEBA EL ALIAS DE LA CLAVE AJENA. Si estuviera mal, PostgREST
    // devolvería PGRST201 por ambigüedad —hay dos FKs hacia `profiles`— y esto reventaría.
    final List<FollowEdge> seguidores = await betoFollows.followers(beto.userId);
    expect(seguidores.map((FollowEdge e) => e.profile.userId), <String>[
      ana.userId,
    ]);
    expect(seguidores.single.profile.displayName, 'ana');
    expect(seguidores.single.profile.tag, isNotNull);

    final List<FollowEdge> siguiendo = await anaFollows.following(ana.userId);
    expect(siguiendo.map((FollowEdge e) => e.profile.userId), <String>[
      beto.userId,
    ]);
  });

  test('messaging: enviar, bandeja de los dos lados, hilo e input', () async {
    final SupabaseMessagingRepository anaMsg = SupabaseMessagingRepository(
      ana.client,
    );
    final SupabaseMessagingRepository carlaMsg = SupabaseMessagingRepository(
      carla.client,
    );

    final ({
      Message message,
      int? messagesLeft,
      bool idempotentReplay,
    })
    enviado = await anaMsg.send(
      recipientId: carla.userId,
      content: 'Hola Carla, ¿cómo estás?',
      idempotencyKey: '11111111-1111-4111-8111-111111111111',
    );

    expect(enviado.message.fromMe, isTrue);
    expect(enviado.idempotentReplay, isFalse);
    // RN-01: 5 en total, uno gastado.
    expect(enviado.messagesLeft, 4);

    // Idempotencia: el MISMO cuerpo devuelve el MISMO mensaje con 200, no un 409.
    final ({Message message, int? messagesLeft, bool idempotentReplay})
    reintento = await anaMsg.send(
      recipientId: carla.userId,
      content: 'Hola Carla, ¿cómo estás?',
      idempotencyKey: '11111111-1111-4111-8111-111111111111',
    );
    expect(reintento.idempotentReplay, isTrue);
    expect(reintento.message.id, enviado.message.id);

    // RN-02: la solicitud enviada va a MIS contactos.
    final InboxSnapshot deAna = await anaMsg.inbox();
    expect(deAna.contacts.map((ConversationSummary c) => c.otherUserId), <String>[
      carla.userId,
    ]);
    expect(deAna.contacts.single.pendingAcceptance, isTrue);
    expect(deAna.contacts.single.lastMessage!.fromMe, isTrue);
    expect(deAna.requests, isEmpty);

    // RN-03: la recibida va a SOLICITUDES.
    final InboxSnapshot deCarla = await carlaMsg.inbox();
    expect(deCarla.contacts, isEmpty);
    expect(deCarla.requests.single.otherUserId, ana.userId);
    expect(deCarla.requestsCount, 1);
    expect(deCarla.requests.single.lastMessage!.fromMe, isFalse);
    // RN-30: las filas de Solicitudes NO traen el punto de actividad.
    expect(deCarla.requests.single.isActive, isNull);

    // §9.2 fila 2 para Ana: activa, con 4 restantes.
    final MessageThreadPage hiloAna = await anaMsg.thread(
      deAna.contacts.single.conversationId,
    );
    expect(hiloAna.input, const MessageInputLimited(4));
    expect(hiloAna.messages.single.content, 'Hola Carla, ¿cómo estás?');
    expect(hiloAna.messages.single.fromMe, isTrue);

    // §9.2 fila 4 para Carla: las cuatro acciones en vez del input.
    final MessageThreadPage hiloCarla = await carlaMsg.thread(
      deCarla.requests.single.conversationId,
    );
    expect(hiloCarla.input, const MessageInputAwaitingDecision());
    expect(hiloCarla.messages.single.fromMe, isFalse);
  });

  test('los 5 de RN-01 se agotan y el input queda inerte con el texto del ADR 0022', () async {
    final SupabaseMessagingRepository anaMsg = SupabaseMessagingRepository(
      ana.client,
    );
    final String conversationId = (await anaMsg.inbox())
        .contacts
        .firstWhere((ConversationSummary c) => c.otherUserId == carla.userId)
        .conversationId;

    // Ya va uno enviado; quedan 4.
    for (int i = 2; i <= 5; i++) {
      await anaMsg.send(
        recipientId: carla.userId,
        content: 'Mensaje $i',
        idempotencyKey: '2222222$i-2222-4222-8222-222222222222',
      );
    }

    final MessageThreadPage hilo = await anaMsg.thread(conversationId);
    expect(hilo.input, MessageInputInert(kMessageInputNotice));

    // Y el sexto es un 422 traducido, no un fallo mudo (RN-21).
    await expectLater(
      anaMsg.send(
        recipientId: carla.userId,
        content: 'Mensaje 6',
        idempotencyKey: '33333333-3333-4333-8333-333333333333',
      ),
      throwsA(
        isA<SocialFailure>()
            .having(
              (SocialFailure f) => f.kind,
              'kind',
              SocialFailureKind.limitReached,
            )
            .having((SocialFailure f) => f.message, 'message', kMessageInputNotice),
      ),
    );
  });

  test('la búsqueda en la conversación devuelve offsets utilizables', () async {
    final SupabaseMessagingRepository anaMsg = SupabaseMessagingRepository(
      ana.client,
    );
    final String conversationId = (await anaMsg.inbox())
        .contacts
        .firstWhere((ConversationSummary c) => c.otherUserId == carla.userId)
        .conversationId;

    final MessageSearchResult result = await anaMsg.search(
      conversationId,
      'como',
    );
    expect(result.total, greaterThanOrEqualTo(1));
    expect(result.searchLimit, 1000);

    // El offset tiene que caer dentro del texto real: es lo que la burbuja usa para resaltar.
    final MessageSearchHit hit = result.hits.first;
    final Message mensaje = (await anaMsg.thread(
      conversationId,
    )).messages.firstWhere((Message m) => m.id == hit.messageId);
    final ({int start, int end}) offset = hit.offsets.first;
    expect(offset.end, lessThanOrEqualTo(mensaje.content!.length));
    expect(
      mensaje.content!.substring(offset.start, offset.end).toLowerCase(),
      'cómo',
    );
  });

  test('actividad: el latido y el estado, booleano y nunca una marca de tiempo', () async {
    final SupabaseActivityRepository anaAct = SupabaseActivityRepository(
      ana.client,
    );
    await anaAct.heartbeat();

    final Map<String, bool> estado = await anaAct.activeStatus(<String>[
      ana.userId,
      beto.userId,
    ]);
    // Ana acaba de latir; Beto no ha latido nunca.
    expect(estado[ana.userId], isTrue);
    expect(estado[beto.userId], isFalse);
  });

  test('connect-feed responde y NINGÚN candidato trae dato del Art. 9', () async {
    final ConnectFeedPage page = await SupabaseConnectRepository(
      ana.client,
    ).feed();

    // La comprobación de verdad es la del modelo (no hay campo donde meterlo), pero esto verifica
    // que el CONTRATO tampoco lo manda: si el backend empezara a devolver una categoría, el
    // parseo la ignoraría en silencio y nadie se enteraría.
    for (final ConnectCandidate c in page.candidates) {
      expect(c.userId, isNotEmpty);
      expect(c.tag, isNotEmpty);
    }
    expect(page.candidates.map((ConnectCandidate c) => c.userId), isNot(contains(ana.userId)));
  });

  test('bloquear archiva la conversación del bloqueador y no toca la del bloqueado', () async {
    await SupabaseModerationRepository(carla.client).block(ana.userId);

    // RN-22: desaparece de la bandeja de quien bloquea.
    final InboxSnapshot deCarla = await SupabaseMessagingRepository(
      carla.client,
    ).inbox();
    expect(
      deCarla.requests.map((ConversationSummary c) => c.otherUserId),
      isNot(contains(ana.userId)),
    );

    // RN-23: al bloqueado NO se le toca nada. Su conversación sigue ahí, con el mismo texto inerte
    // que tenía por el cupo agotado — indistinguible.
    final SupabaseMessagingRepository anaMsg = SupabaseMessagingRepository(
      ana.client,
    );
    final ConversationSummary conv = (await anaMsg.inbox()).contacts.firstWhere(
      (ConversationSummary c) => c.otherUserId == carla.userId,
    );
    expect(
      (await anaMsg.thread(conv.conversationId)).input,
      MessageInputInert(kMessageInputNotice),
    );
  });
}
