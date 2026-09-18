import 'package:flutter/material.dart';

import '../../../../core/theming/grasp_palette.dart';
import '../../../../core/theming/app_theme.dart';

/// El menú de tres puntos del §9.3 — las **siete** entradas, en su orden.
///
/// Boceto: `06-messaging-inbox.jpeg` por derivación («Chat de una conversación», README de
/// `pictures/screens`). De ahí salen el radio grande de la hoja, el blanco de la superficie y el
/// lila de los iconos; el patrón de hoja con `ListTile` ya lo usa el menú largo de [MessageBubble].
///
/// ## Las tres que no hacen nada, y por qué no lo disimulan
///
/// Campana, carpeta y pánico son «Solo frontend» en el §9.3. La regla que las gobierna es la de los
/// *Global Constraints* del plan —«un botón que no hace nada se declara»— y su mitad más
/// importante: **ninguno puede afirmar haber hecho algo**. Por eso:
///
///  - La **campana** guarda su valor de verdad (`set_notifications`) y lleva debajo, **siempre
///    visible y antes de que nadie la toque**, que las notificaciones push todavía no existen. Se
///    dice ahí y no en un modal posterior a propósito: un aviso que aparece *después* de actuar es
///    ceremonia alrededor de un no-op; uno que se lee *antes* es información para decidir, el mismo
///    principio que obliga al modal de bloqueo a decir dónde se deshace.
///  - La **carpeta** navega de verdad, como pide el §9.3, a una pantalla que está vacía **y lo
///    dice** (`ChatFilesScreen`).
///  - El **pánico** abre su modal, y el modal empieza diciendo que no está disponible. No hay un
///    botón «Activar» que no active nada: confirmar algo que no ocurre es mentir por implicatura.
///
/// ## Las dos que sí hacen algo, y una de ellas se puede deshacer desde Perfil
///
/// Bloqueo y reporte persisten (decisión 6 del plan), así que su modal **sí** puede confirmar. El de
/// bloqueo dice con esas palabras dónde se deshace (ADR 0027, `block-remove`): confirmar una acción
/// sin saber cómo revertirla es peor que no poder revertirla.
class ConversationMenu extends StatelessWidget {
  const ConversationMenu({
    super.key,
    required this.notificationsEnabled,
    required this.onToggleNotifications,
    required this.onOpenFiles,
    required this.onSearch,
    required this.onDeleteHistory,
    required this.onBlock,
    required this.onReport,
    required this.onPanic,
    this.hasConversation = true,
  });

  // ── Las siete entradas ────────────────────────────────────────────────────
  static const Key notificationsKey = Key('conversation-menu-notifications');
  static const Key notificationsSwitchKey = Key('conversation-menu-notifications-switch');
  static const Key filesKey = Key('conversation-menu-files');
  static const Key searchKey = Key('conversation-menu-search');
  static const Key deleteHistoryKey = Key('conversation-menu-delete-history');
  static const Key blockKey = Key('conversation-menu-block');
  static const Key reportKey = Key('conversation-menu-report');
  static const Key panicKey = Key('conversation-menu-panic');

  // ── Los modales ───────────────────────────────────────────────────────────
  static const Key cancelKey = Key('conversation-menu-cancel');
  static const Key deleteHistoryConfirmKey = Key('conversation-menu-delete-history-confirm');
  static const Key blockConfirmKey = Key('conversation-menu-block-confirm');
  static const Key reportConfirmKey = Key('conversation-menu-report-confirm');
  static const Key panicConfirmKey = Key('conversation-menu-panic-confirm');

  static const String notifications = 'Notificaciones';
  static const String files = 'Archivos del chat';
  static const String search = 'Buscar en la conversación';
  static const String deleteHistory = 'Eliminar historial de chat';
  static const String block = 'Bloquear usuario';
  static const String report = 'Reportar usuario';
  static const String panic = 'Botón de pánico';

  /// §9.3 punto 1 es «sin efecto funcional». Se dice **antes** de tocar el toggle, no después: un
  /// interruptor que se puede encender sin avisar promete avisos que no van a llegar.
  ///
  /// TODO(§13 · `docs/pending-messaging.md` § 6 «Notificaciones push»): falta el sistema de push
  /// entero —proveedor, tokens de dispositivo, entrega— y decidir la **granularidad** (por
  /// conversación, global, o las dos). El ajuste por conversación ya está persistido, así que la
  /// decisión global tendrá que respetarlo o migrarlo.
  static const String notificationsUnavailable =
      'Las notificaciones push todavía no están disponibles. Tu preferencia queda guardada.';

  /// TODO(§13 · `docs/pending-messaging.md` § 8 «Botón de pánico»): lo que falta primero **no es
  /// código, es la definición funcional** — producto debe especificar qué dispara (contacto de
  /// emergencia, recursos de ayuda, corte de la conversación, o varias) antes de que nadie escriba
  /// `panic-trigger`. El diseño del maestro asume sala/llamada con buffer de audio, y **en una
  /// conversación de texto no hay buffer que subir**: el mecanismo no se hereda.
  static const String panicUnavailable =
      'El botón de pánico todavía no está disponible en Grasp. Al confirmar no se avisa a nadie '
      'ni se corta la conversación.';

  /// **La frase entera es el requisito**: es lo único que le da a la persona la información para
  /// decidir. Hasta el ADR 0027 decía «no se puede deshacer **todavía**… **por ahora**», que era
  /// honesto —no prometía permanencia eterna— pero desde que existe `block-remove` prometería al
  /// revés. Una frase que apunta a la pantalla donde se deshace vale más que una que advierte de
  /// una limitación que ya no hay.
  static const String blockWarning =
      'Dejaréis de poder escribiros y esta conversación desaparecerá de tus mensajes. '
      'Podrás deshacerlo desde Perfil → Privacidad → Usuarios bloqueados.';

  static const String reportWarning =
      'Se enviará tu reporte al equipo de Grasp junto con esta conversación, y se bloqueará '
      'también a esta persona.';

  final bool notificationsEnabled;
  final ValueChanged<bool> onToggleNotifications;
  final VoidCallback onOpenFiles;
  final VoidCallback onSearch;
  final VoidCallback onDeleteHistory;
  final VoidCallback onBlock;
  final VoidCallback onReport;
  final VoidCallback onPanic;

  /// `false` al entrar desde Conectar sin haber escrito nada (`RN-39`): todavía no hay conversación
  /// que silenciar, en la que buscar ni cuyo historial vaciar. Bloquear y reportar **sí** valen —se
  /// puede querer cortar antes de escribir—, así que las siete entradas siguen estando y las cuatro
  /// que necesitan hilo se apagan. Apagadas y no ausentes: un menú que cambia de forma según el
  /// estado obliga a buscar de nuevo dónde estaba cada cosa.
  final bool hasConversation;

  @override
  Widget build(BuildContext context) {
    // Scroll y no `Column` a secas: **siete** entradas con su subtítulo y su separador no caben en
    // la altura por defecto de una hoja modal (9/16 de la pantalla), y lo que no cabe se recorta —
    // el botón de pánico, que es el último, sería justo lo primero en desaparecer. Se descubrió
    // porque el propio test reventó con un `RenderFlex overflowed by 127 pixels`; en un móvil real
    // habría sido una franja rayada tapando la última entrada.
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
          _Entrada(
            itemKey: notificationsKey,
            icon: Icons.notifications_none_rounded,
            label: notifications,
            subtitle: notificationsUnavailable,
            enabled: hasConversation,
            trailing: Switch(
              key: notificationsSwitchKey,
              value: notificationsEnabled,
              // §9.3: «derecha = activo y coloreado, izquierda = apagado y gris».
              activeThumbColor: context.palette.onBrand,
              activeTrackColor: context.palette.brand,
              inactiveThumbColor: context.palette.surface,
              inactiveTrackColor: context.palette.outline,
              onChanged: hasConversation ? onToggleNotifications : null,
            ),
            // La fila entera acompaña al interruptor, que es lo que se espera de un toggle.
            onTap: hasConversation
                ? () => onToggleNotifications(!notificationsEnabled)
                : null,
          ),
          _Entrada(
            itemKey: filesKey,
            icon: Icons.folder_outlined,
            label: files,
            // El `>` del §9.3: esta entrada NAVEGA, no abre un interruptor.
            trailing: Icon(
              Icons.chevron_right_rounded,
              color: context.palette.textMuted,
            ),
            onTap: onOpenFiles,
          ),
          _Entrada(
            itemKey: searchKey,
            icon: Icons.search_rounded,
            label: search,
            enabled: hasConversation,
            onTap: hasConversation ? onSearch : null,
          ),
          _Entrada(
            itemKey: deleteHistoryKey,
            icon: Icons.delete_outline_rounded,
            label: deleteHistory,
            enabled: hasConversation,
            onTap: hasConversation ? onDeleteHistory : null,
          ),
          _Entrada(
            itemKey: blockKey,
            icon: Icons.person_remove_outlined,
            label: block,
            onTap: onBlock,
          ),
          _Entrada(
            itemKey: reportKey,
            icon: Icons.campaign_outlined,
            label: report,
            onTap: onReport,
          ),
          // §9.3 entrada 7: «justo debajo de Reportar, **en rojo y visualmente separado** del
          // resto». La separación es el `Divider` con aire a los dos lados; sin ella, un botón rojo
          // pegado a los demás se pulsa por inercia al bajar el dedo.
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.md,
            ),
            child: Divider(height: 1, color: context.palette.outline),
          ),
          _Entrada(
            itemKey: panicKey,
            icon: Icons.warning_amber_rounded,
            label: panic,
            danger: true,
            onTap: onPanic,
          ),
          const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
  }
}

class _Entrada extends StatelessWidget {
  const _Entrada({
    required this.itemKey,
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
    this.trailing,
    this.danger = false,
    this.enabled = true,
  });

  final Key itemKey;
  final IconData icon;
  final String label;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool danger;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final Color color = !enabled
        ? context.palette.textMuted
        : (danger ? context.palette.error : context.palette.textPrimary);

    return ListTile(
      key: itemKey,
      enabled: enabled,
      leading: Icon(icon, color: danger ? context.palette.error : context.palette.brandStrong),
      title: Text(
        label,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: context.palette.textMuted,
                // Ver la nota de `PrivacySection`: `labelSmall` viene en `w500` y dejaría el
                // subtítulo más grueso que la entrada que explica.
                fontWeight: FontWeight.w400,
              ),
            ),
      trailing: trailing,
      onTap: onTap,
    );
  }
}

/// Un modal de confirmación de los del §9.3.
///
/// Devuelve `true` solo si se confirmó. **[warning] se pinta siempre**, y es donde vive la frase
/// obligatoria del bloqueo: un modal cuyo cuerpo fuera opcional permitiría un segundo sitio de
/// llamada que se la dejara fuera sin que nada lo delatara.
///
/// ## [dismissOnly], y por qué el pánico lo necesita
///
/// Un modal que **no hace nada** no puede ofrecer «Cancelar» y «Entendido»: dar a elegir entre dos
/// botones afirma, por la sola forma del diálogo, que uno de los dos **hace algo** — y el §9.3 dice
/// que el pánico no hace nada todavía. Es la misma mentira que el texto acaba de desmentir, contada
/// otra vez con la disposición en vez de con palabras. Con [dismissOnly] queda un único botón que
/// cierra, que es la única acción que existe de verdad.
///
/// Se vio en el emulador, no en un test: los tests comprobaban el texto y que no se llamara a
/// ninguna repository, y las dos cosas seguían siendo ciertas con los dos botones puestos.
Future<bool> confirmarAccion(
  BuildContext context, {
  required String title,
  required String warning,
  required String confirmLabel,
  required Key confirmKey,
  bool danger = true,
  bool dismissOnly = false,
}) async {
  final bool? confirmado = await showDialog<bool>(
    context: context,
    builder: (BuildContext dialog) => AlertDialog(
      backgroundColor: context.palette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(AppRadius.card)),
      ),
      title: Text(title),
      content: Text(warning),
      actions: <Widget>[
        if (!dismissOnly)
          TextButton(
            key: ConversationMenu.cancelKey,
            onPressed: () => Navigator.of(dialog).pop(false),
            child: const Text('Cancelar'),
          ),
        FilledButton(
          key: confirmKey,
          onPressed: () => Navigator.of(dialog).pop(true),
          style: FilledButton.styleFrom(
            backgroundColor: danger ? context.palette.error : context.palette.brandStrong,
            foregroundColor: context.palette.onBrand,
          ),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return confirmado ?? false;
}
