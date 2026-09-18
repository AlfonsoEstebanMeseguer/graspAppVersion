import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theming/grasp_palette.dart';
import '../../../../core/theming/app_theme.dart';
import '../../../../domain/social/message.dart';
import '../../../../domain/social/message_input_state.dart';
import '../../application/conversation_controller.dart';
import 'message_bubble.dart';

/// `RN-26`: máximo 1000 caracteres por mensaje.
///
/// Espejo de `MAX_MESSAGE_LENGTH` en `_shared/validation.ts`. Un test lo compara con el `.ts` real,
/// por el mismo motivo que [kMessageInputNotice]: Dart y Deno no pueden compartir una constante.
const int kMaxMessageLength = 1000;

/// `RN-26`: el contador aparece **solo a partir de aquí**, no antes.
const int kCounterFrom = 900;

/// El input del §9.1 — campo de texto y botón de enviar.
///
/// ## Sin selector de emojis, y es una regla, no un descuido
///
/// El §9.1 original decía «campo de texto + **selector de emojis** + botón de enviar». La enmienda
/// nº 10 de la spec lo retiró: gana `RN-33`, *«los emoticonos no aparecen desde un botón, se
/// escriben desde el teclado de la interfaz del propio móvil»*. La app se limita a **pintar** lo
/// que el teclado del sistema escriba, que es lo que hace un `TextField` sin tocar nada.
///
/// ## Qué pinta cada estado del §9.2
///
/// El estado llega como [MessageInputState] ya interpretado, y el `switch` es exhaustivo sobre las
/// cuatro variantes. Las filas 3 y 5 del §9.2 —cupo agotado y bloqueo— comparten
/// [MessageInputInert], así que **comparten este código entero**: no hay rama que pueda pintar un
/// icono distinto ni un texto distinto para el bloqueo, porque no hay dos ramas (`RN-23`,
/// ADR 0022). La fila 4 no llega aquí: la pantalla pone `RequestActionsBar` en su lugar.
class MessageComposer extends StatefulWidget {
  const MessageComposer({
    super.key,
    required this.controller,
    required this.input,
    required this.otherDisplayName,
    this.target,
    this.onSend,
    this.onCancelTarget,
  });

  static const Key fieldKey = Key('conversation-composer-field');
  static const Key sendKey = Key('conversation-composer-send');
  static const Key counterKey = Key('conversation-composer-counter');
  static const Key noticeKey = Key('conversation-composer-notice');
  static const Key replyPreviewKey = Key('conversation-composer-reply');

  static const String hint = 'Escribe un mensaje…';

  /// Lo dueño del texto es la pantalla y no este widget: el texto tiene que **sobrevivir a un
  /// envío fallido** para que el reintento tenga qué reintentar, y un controlador creado aquí
  /// dentro se perdería en cuanto el estado del input cambiara de variante y el widget se
  /// reconstruyera con otra forma.
  final TextEditingController controller;

  final MessageInputState input;
  final String otherDisplayName;

  /// La cita o la edición en curso (`RN-28`).
  final ComposerTarget? target;

  final Future<void> Function()? onSend;
  final VoidCallback? onCancelTarget;

  @override
  State<MessageComposer> createState() => _MessageComposerState();
}

class _MessageComposerState extends State<MessageComposer> {
  bool _enviando = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_alEscribir);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_alEscribir);
    super.dispose();
  }

  @override
  void didUpdateWidget(MessageComposer old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_alEscribir);
      widget.controller.addListener(_alEscribir);
    }
  }

  /// Solo para que el contador y el botón de enviar se repinten con la longitud.
  void _alEscribir() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final MessageInputState input = widget.input;

    return Container(
      decoration: BoxDecoration(
        color: context.palette.surface,
        border: Border(top: BorderSide(color: context.palette.containerSubtle)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
            AppSpacing.sm,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (widget.target != null) _preview(context),
              // «Deshabilitado + aviso» y «sustituido por» son dos cosas distintas, y el §9.2 usa
              // esas dos palabras a propósito: las filas 3 y 5 **conservan el campo**, apagado,
              // con la explicación debajo; la fila 4 lo sustituye entero, y esa no llega aquí.
              switch (input) {
                MessageInputInert(:final String notice) => Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _campo(context, habilitado: false),
                    const SizedBox(height: AppSpacing.sm),
                    _Notice(text: notice),
                  ],
                ),
                MessageInputOpen() ||
                MessageInputLimited() => _campo(context, habilitado: true),
                // La fila 4 no pasa por aquí: la pantalla pone las cuatro acciones de `RN-04` en
                // lugar del compositor entero. Si llegara, un campo vivo sin sitio a donde enviar
                // sería peor que nada, así que se cae al mismo aviso que el resto.
                MessageInputAwaitingDecision() => const _Notice(
                  text: kMessageInputNotice,
                ),
              },
            ],
          ),
        ),
      ),
    );
  }

  Widget _campo(BuildContext context, {required bool habilitado}) {
    final int longitud = _puntosDeCodigo(widget.controller.text);
    final bool hayTexto = widget.controller.text.trim().isNotEmpty;
    final bool puedeEnviar = habilitado && hayTexto && !_enviando;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  // Apagado se hunde en el fondo de la pantalla (que es `purple50`); encendido
                  // resalta en blanco. Sin esta diferencia el campo inerte del §9.2 se ve
                  // exactamente igual que uno donde sí se puede escribir, y la única pista de que
                  // no se puede es el aviso de abajo — que hay que leer entero para enterarse.
                  color: habilitado ? context.palette.surface : context.palette.canvas,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: habilitado
                        ? context.palette.outline
                        : context.palette.containerSubtle,
                  ),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: 2,
                ),
                child: TextField(
                  key: MessageComposer.fieldKey,
                  controller: widget.controller,
                  enabled: habilitado,
                  // El teclado del sistema es la ÚNICA fuente de emojis (`RN-33`). No se restringe
                  // el tipo de teclado ni se filtra la entrada: lo que el móvil escriba, se pinta.
                  keyboardType: TextInputType.multiline,
                  textCapitalization: TextCapitalization.sentences,
                  minLines: 1,
                  maxLines: 5,
                  inputFormatters: <TextInputFormatter>[
                    const _CodePointLimit(kMaxMessageLength),
                  ],
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: context.palette.textPrimary,
                  ),
                  // El campo va SIN cromo propio: la píldora la pinta el `Container` de fuera.
                  //
                  // No basta con `border: InputBorder.none`. El `inputDecorationTheme` de
                  // `AppTheme` trae `filled: true` y un `enabledBorder`/`focusedBorder` con marco
                  // redondeado, y **los de estado ganan sobre `border`**: el resultado era una
                  // píldora dentro de otra píldora, con dos bordes lila concéntricos. Se vio en el
                  // emulador; ningún test de widget lo mira.
                  decoration: const InputDecoration(
                    hintText: MessageComposer.hint,
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    focusedErrorBorder: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Semantics(
              button: true,
              label: 'Enviar mensaje',
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: puedeEnviar
                      ? LinearGradient(colors: context.palette.primaryCta)
                      : null,
                  // Apagado se queda MUY por detrás del encendido. Con `purple200` de fondo e
                  // icono blanco parecía pulsable estando muerto, y un botón que promete y no
                  // responde es peor que uno que se ve claramente apagado.
                  color: puedeEnviar ? null : context.palette.containerSubtle,
                ),
                child: IconButton(
                  key: MessageComposer.sendKey,
                  onPressed: puedeEnviar ? _enviar : null,
                  icon: const Icon(Icons.send_rounded, size: 20),
                  color: context.palette.onBrand,
                  disabledColor: context.palette.chip,
                  tooltip: 'Enviar',
                ),
              ),
            ),
          ],
        ),
        // `RN-26`: visible SOLO a partir de 900. Antes de ese punto no hay nada que avisar y un
        // contador permanente convierte cada mensaje en un examen.
        if (longitud >= kCounterFrom) ...<Widget>[
          const SizedBox(height: AppSpacing.xs),
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: Text(
              '$longitud/$kMaxMessageLength',
              key: MessageComposer.counterKey,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                // En el tope cambia de color: `RN-21` obliga a decir qué límite se alcanzó, y a
                // 1000/1000 el número solo no explica por qué el teclado dejó de responder.
                color: longitud >= kMaxMessageLength
                    ? context.palette.error
                    : context.palette.textMuted,
                fontWeight: longitud >= kMaxMessageLength
                    ? FontWeight.w700
                    : FontWeight.w500,
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// La cita o el aviso de edición encima del campo (`RN-28`).
  Widget _preview(BuildContext context) {
    final ComposerTarget target = widget.target!;
    final Message m = target.message;
    final ThemeData theme = Theme.of(context);

    final String titulo = switch (target) {
      ComposerReply() => m.fromMe
          ? 'Respondiendo a tu mensaje'
          : 'Respondiendo a ${widget.otherDisplayName}',
      ComposerEdit() => 'Editando tu mensaje',
    };

    return Container(
      key: MessageComposer.replyPreviewKey,
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm + 2,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: context.palette.canvas,
        borderRadius: BorderRadius.circular(12),
        border: Border(
          left: BorderSide(color: context.palette.iconSoft, width: 3),
        ),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  titulo,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: context.palette.brandStrong,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  m.content ?? MessageBubble.tombstone,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: context.palette.textMuted,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: widget.onCancelTarget,
            icon: const Icon(Icons.close_rounded, size: 18),
            color: context.palette.textMuted,
            tooltip: 'Cancelar',
          ),
        ],
      ),
    );
  }

  Future<void> _enviar() async {
    final Future<void> Function()? onSend = widget.onSend;
    if (onSend == null) return;

    setState(() => _enviando = true);
    try {
      await onSend();
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }
}

/// El aviso del input inerte — §9.2 filas 3 y 5.
///
/// **Un solo widget para los dos casos.** No recibe ningún motivo, así que no hay nada que pueda
/// pintar distinto: la garantía de `RN-23` está en la forma del código, no en la disciplina de
/// quien lo lea. El icono es el mismo por la misma razón — hay uno solo.
class _Notice extends StatelessWidget {
  const _Notice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: MessageComposer.noticeKey,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.md - 2,
      ),
      decoration: BoxDecoration(
        color: context.palette.canvas,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.palette.outline),
      ),
      child: Row(
        children: <Widget>[
          // Un reloj: lo que el texto dice es «todavía no», no «nunca». Cualquier icono con
          // semántica de prohibición delataría el bloqueo justo donde el texto lo tapa.
          Icon(
            Icons.schedule_rounded,
            size: 18,
            color: context.palette.brandStrong,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: context.palette.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

/// Corta en [max] **puntos de código**, no en unidades UTF-16.
///
/// `LengthLimitingTextInputFormatter` cuenta *grafemas* y `String.length` cuenta UTF-16; el backend
/// cuenta puntos de código, que es lo que mide `char_length` en Postgres
/// (`normalizeMessageContent`). Las tres cuentas dan números distintos en cuanto hay un emoji:
/// «😀» es 1 grafema, 1 punto de código y **2** unidades UTF-16.
///
/// Que el cliente use otra cuenta que el servidor tiene dos consecuencias, y las dos son malas: si
/// cuenta de menos deja escribir un mensaje que el backend devuelve con un 400 incomprensible, y
/// si cuenta de más corta mensajes que la base habría aceptado. Se cuenta igual que allí.
///
/// **No trunca**: si la edición se pasa del tope, se rechaza entera y se conserva la anterior. Es
/// literalmente `RN-26` — *«al llegar a 1000 se impide seguir escribiendo (no se trunca en
/// silencio)»*.
class _CodePointLimit extends TextInputFormatter {
  const _CodePointLimit(this.max);

  final int max;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue previo,
    TextEditingValue nuevo,
  ) {
    if (_puntosDeCodigo(nuevo.text) <= max) return nuevo;
    // Si lo anterior ya se pasaba —solo puede venir de fuera del teclado— se recorta a la cota, o
    // el campo se quedaría bloqueado sin forma de arreglarlo.
    if (_puntosDeCodigo(previo.text) > max) {
      final String cortado = String.fromCharCodes(previo.text.runes.take(max));
      return TextEditingValue(
        text: cortado,
        selection: TextSelection.collapsed(offset: cortado.length),
      );
    }
    return previo;
  }
}

int _puntosDeCodigo(String texto) => texto.runes.length;
