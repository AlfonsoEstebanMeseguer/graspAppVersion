import 'package:flutter/material.dart';

import '../../../../core/theming/grasp_palette.dart';
import '../../../../core/theming/app_theme.dart';
import '../../../../domain/profile/avatar_type.dart';
import '../../../../domain/social/message.dart';
import 'social_avatar.dart';

/// Una burbuja del §9.1 — «estilo WhatsApp/Instagram».
///
/// Boceto: `06-messaging-inbox.jpeg`. De ahí salen el radio grande, el tinte lila de la burbuja
/// destacada frente al blanco de las demás, la hora dentro de la burbuja y la foto pegada a su
/// izquierda. Lo que el boceto **no** tiene es el segundo lado —es un chat de sala, todos los
/// mensajes son ajenos—, así que la alineación de los propios sale del §9.1: *«Mensajes propios
/// alineados a un lado con un color; los del otro al contrario»*.
///
/// ## La foto solo acompaña a las burbujas del otro
///
/// El §9.1 dice «foto de perfil junto a la burbuja» sin decir de quién, pero nombra el estilo:
/// WhatsApp/Instagram. En los dos, la cara propia no se repite en cada burbuja — la cabecera ya
/// dice con quién se habla, y una columna de avatares idénticos a la derecha come ancho de texto
/// sin añadir información.
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.otherDisplayName,
    this.photoUrl,
    this.presetAvatar,
    this.onReply,
    this.onEdit,
    this.onDeleteForMe,
    this.onDeleteForAll,
    this.anchor,
    this.highlights = const <({int start, int end})>[],
  });

  /// `RN-28`: lo que sustituye al texto de un mensaje borrado para todos.
  static const String tombstone = 'Este mensaje ha sido eliminado';

  /// `RN-28`: el tag que ven **los dos**.
  static const String editedTag = 'editado';

  /// Una cita que quien mira no puede ver: borrada «para mí» (`RN-28`), anterior a su `cleared_at`
  /// (`RN-27`) o lápida. Se dice, en vez de omitir la cita y romper el hilo.
  static const String quoteUnavailable = 'Mensaje no disponible';

  static const Key replyKey = Key('message-action-reply');
  static const Key editKey = Key('message-action-edit');
  static const Key deleteForMeKey = Key('message-action-delete-for-me');
  static const Key deleteForAllKey = Key('message-action-delete-for-all');

  final Message message;
  final String otherDisplayName;
  final String? photoUrl;
  final AvatarType? presetAvatar;

  final void Function(Message)? onReply;
  final void Function(Message)? onEdit;
  final void Function(Message)? onDeleteForMe;
  final void Function(Message)? onDeleteForAll;

  /// Dónde agarrar esta burbuja para que la flecha del §9.4 pueda arrastrar la lista hasta ella.
  ///
  /// Va aparte de la `key` del widget porque son dos cosas distintas: la `key` la usa Flutter para
  /// reconciliar la lista, y ésta la usa `Scrollable.ensureVisible` para localizar el
  /// `BuildContext`. Una sola clave no puede hacer las dos: la de reconciliación se compara por
  /// igualdad y la de localización tiene que ser una `GlobalKey` viva y única en todo el árbol.
  final GlobalKey? anchor;

  /// Tramos `[start, end)` a resaltar (§9.4), **en unidades UTF-16 del texto original**.
  ///
  /// Vienen de `messaging-search` y se usan **tal cual**. No se recalculan aquí ni se pasan por
  /// `findMatches`: normalizar a los dos lados con reglas distintas desplaza el resaltado, que es
  /// el fallo que `_shared/text-search.ts` documenta arriba del todo. Un mensaje que el backend no
  /// devolvió llega con la lista vacía y se pinta como siempre, que es como se cumple lo de «no
  /// busca en borrados para mí, ni antes de mi `cleared_at`, ni en lápidas» sin saber nada de esas
  /// tres reglas.
  final List<({int start, int end})> highlights;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool propio = message.fromMe;

    final Widget burbuja = Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * 0.72,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md - 2,
        vertical: AppSpacing.sm + 2,
      ),
      decoration: BoxDecoration(
        color: propio ? context.palette.containerSubtle : context.palette.surface,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          bottomLeft: Radius.circular(propio ? 18 : 4),
          bottomRight: Radius.circular(propio ? 4 : 18),
        ),
        border: propio ? null : Border.all(color: context.palette.outline),
        boxShadow: <BoxShadow>[
          BoxShadow(color: context.palette.shadow, blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (message.replyTo != null) ...<Widget>[
            _Quote(quote: message.replyTo!, otherDisplayName: otherDisplayName),
            const SizedBox(height: AppSpacing.xs + 2),
          ],
          _cuerpo(theme),
          const SizedBox(height: 2),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (message.edited && !message.deletedForAll) ...<Widget>[
                Text(
                  editedTag,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: context.palette.textMuted,
                    fontStyle: FontStyle.italic,
                  ),
                ),
                const SizedBox(width: AppSpacing.xs + 2),
              ],
              Text(
                _hora(message.createdAt),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: context.palette.textMuted,
                ),
              ),
            ],
          ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      child: Align(
        alignment: propio ? Alignment.centerRight : Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            if (!propio) ...<Widget>[
              SocialAvatar(
                displayName: otherDisplayName,
                presetAvatar: presetAvatar,
                photoUrl: photoUrl,
                size: 30,
              ),
              const SizedBox(width: AppSpacing.sm),
            ],
            Flexible(
              child: GestureDetector(
                // El ancla va sobre la burbuja y no sobre el `Padding` de fuera para que el
                // `ensureVisible` del §9.4 centre el globo, no el hueco que lo rodea.
                key: anchor,
                onLongPress: _tieneAcciones ? () => _menu(context) : null,
                child: burbuja,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// El texto, o la lápida.
  ///
  /// La bandera manda sobre el contenido **siempre**: el backend fuerza `content: null` en cuanto
  /// hay lápida, pero una burbuja que se fiara del contenido y no de la bandera pintaría el texto
  /// de un mensaje borrado si esa garantía fallara alguna vez. Es una línea de más contra un fallo
  /// que sería irreparable.
  Widget _cuerpo(ThemeData theme) {
    if (message.deletedForAll) {
      return Text(
        tombstone,
        style: theme.textTheme.bodyMedium?.copyWith(
          // `RN-28`: cursiva y un color de fuente distinto del resto de mensajes.
          fontStyle: FontStyle.italic,
          color: theme.palette.textMuted,
        ),
      );
    }

    final TextStyle? base = theme.textTheme.bodyMedium?.copyWith(
      color: theme.palette.textPrimary,
      height: 1.35,
    );
    final String contenido = message.content ?? tombstone;

    if (highlights.isEmpty) return Text(contenido, style: base);

    return Text.rich(
      TextSpan(children: _conResaltado(contenido, base, theme.palette)),
      style: base,
    );
  }

  /// Parte [contenido] en tramos, con los de [highlights] sobre fondo lila.
  ///
  /// ## Se defiende de sus propios offsets, y no es paranoia
  ///
  /// Los offsets los calculó el backend sobre el texto que tenía **en el momento de buscar**. Entre
  /// esa respuesta y este `build` cabe una edición (`RN-28`) llegando por tiempo real, y entonces
  /// apuntan más allá del final. `substring` con un índice fuera de rango es una excepción que se
  /// come la conversación entera; recortar y descartar solo se come el resaltado de ese mensaje.
  List<InlineSpan> _conResaltado(
    String contenido,
    TextStyle? base,
    GraspPalette palette,
  ) {
    final List<({int start, int end})> tramos =
        List<({int start, int end})>.of(highlights)
          ..sort(
            (({int start, int end}) a, ({int start, int end}) b) =>
                a.start.compareTo(b.start),
          );

    final List<InlineSpan> spans = <InlineSpan>[];
    int cursor = 0;

    for (final ({int start, int end}) t in tramos) {
      final int inicio = t.start.clamp(0, contenido.length);
      final int fin = t.end.clamp(0, contenido.length);
      // Se descartan los degenerados y los que se solapan con lo ya pintado: dos rangos solapados
      // se dibujarían uno encima del otro dentro de la burbuja.
      if (fin <= inicio || inicio < cursor) continue;

      if (inicio > cursor) {
        spans.add(TextSpan(text: contenido.substring(cursor, inicio)));
      }
      spans.add(
        TextSpan(
          text: contenido.substring(inicio, fin),
          style: base?.copyWith(
            backgroundColor: palette.chip,
            color: palette.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
      cursor = fin;
    }

    if (cursor < contenido.length) {
      spans.add(TextSpan(text: contenido.substring(cursor)));
    }
    return spans;
  }

  bool get _tieneAcciones =>
      onReply != null ||
      onEdit != null ||
      onDeleteForMe != null ||
      onDeleteForAll != null;

  /// Las acciones de `RN-28`.
  ///
  /// **Borrar para todos y editar solo se ofrecen sobre un mensaje propio**, que es lo que
  /// `messaging-message-actions` acepta. Enseñarlas sobre uno ajeno sería un botón que el backend
  /// rechaza siempre — y sobre una lápida, editar no tiene qué editar.
  Future<void> _menu(BuildContext context) async {
    final bool editable = message.fromMe && !message.deletedForAll;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.palette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (BuildContext sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (onReply != null && !message.deletedForAll)
              _Accion(
                itemKey: replyKey,
                icon: Icons.reply_outlined,
                label: 'Responder',
                onTap: () {
                  Navigator.of(sheet).pop();
                  onReply!(message);
                },
              ),
            if (onEdit != null && editable)
              _Accion(
                itemKey: editKey,
                icon: Icons.edit_outlined,
                label: 'Editar',
                onTap: () {
                  Navigator.of(sheet).pop();
                  onEdit!(message);
                },
              ),
            if (onDeleteForMe != null)
              _Accion(
                itemKey: deleteForMeKey,
                icon: Icons.delete_outline,
                label: 'Eliminar para mí',
                onTap: () {
                  Navigator.of(sheet).pop();
                  onDeleteForMe!(message);
                },
              ),
            if (onDeleteForAll != null && editable)
              _Accion(
                itemKey: deleteForAllKey,
                icon: Icons.delete_forever_outlined,
                label: 'Eliminar para todos',
                danger: true,
                onTap: () {
                  Navigator.of(sheet).pop();
                  onDeleteForAll!(message);
                },
              ),
          ],
        ),
      ),
    );
  }

  static String _hora(DateTime when) =>
      '${when.hour.toString().padLeft(2, '0')}:'
      '${when.minute.toString().padLeft(2, '0')}';
}

/// La cita de `RN-28` dentro de la burbuja que responde.
class _Quote extends StatelessWidget {
  const _Quote({required this.quote, required this.otherDisplayName});

  final MessageQuote quote;
  final String otherDisplayName;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String? content = quote.content;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs + 2,
      ),
      decoration: BoxDecoration(
        color: context.palette.canvas,
        border: Border(left: BorderSide(color: context.palette.iconSoft, width: 3)),
        borderRadius: BorderRadius.all(Radius.circular(8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            quote.fromMe ? 'Tú' : otherDisplayName,
            style: theme.textTheme.labelSmall?.copyWith(
              color: context.palette.brandStrong,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            content ?? MessageBubble.quoteUnavailable,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: context.palette.textMuted,
              fontStyle: content == null ? FontStyle.italic : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _Accion extends StatelessWidget {
  const _Accion({
    required this.itemKey,
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final Key itemKey;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final Color color = danger ? context.palette.error : context.palette.textPrimary;
    return ListTile(
      key: itemKey,
      leading: Icon(icon, color: color),
      title: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: color, fontWeight: FontWeight.w600),
      ),
      onTap: onTap,
    );
  }
}
