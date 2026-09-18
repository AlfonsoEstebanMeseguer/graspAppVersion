import 'package:flutter/material.dart';

import '../../../../core/theming/grasp_palette.dart';
import '../../../../core/theming/app_theme.dart';

/// Las cuatro acciones de `RN-04`, en lugar del input — §9.2 fila 4.
///
/// «**Sustituido** por `Aceptar` / `Ignorar` / `Bloquear` / `Reportar`», dice el §9.2, y por eso
/// esto no es un campo de texto atenuado: el campo **no está**. Quien recibe una solicitud lee el
/// mensaje entero y decide; escribir es lo que hace `Aceptar` (`RN-05`).
///
/// ## Lo que esta barra NO sabe
///
/// No recibe `canSend`, ni el aviso, ni los mensajes restantes. No es ahorro: para una solicitud
/// recibida un `can_send: false` **solo puede venir de un bloqueo** (`RN-08` deja fuera el tope de
/// `RN-01` a quien contesta), así que ese campo aquí es un oráculo. Desde el 2026-08-26 el backend
/// lo emite constante ([ADR 0025](../../../../../docs/decisions/0025-la-fila-4-del-input-se-emite-constante.md));
/// que este widget además **no tenga dónde recibirlo** es la segunda capa.
class RequestActionsBar extends StatelessWidget {
  const RequestActionsBar({
    super.key,
    this.onAccept,
    this.onIgnore,
    this.onBlock,
    this.onReport,
    this.busy = false,
  });

  static const Key acceptKey = Key('request-action-accept');
  static const Key ignoreKey = Key('request-action-ignore');
  static const Key blockKey = Key('request-action-block');
  static const Key reportKey = Key('request-action-report');

  static const String accept = 'Aceptar';
  static const String ignore = 'Ignorar';
  static const String block = 'Bloquear';
  static const String report = 'Reportar';

  /// `RN-05`: pasa a Contactos y los dos escriben sin tope.
  final VoidCallback? onAccept;

  /// `RN-06`: desaparece de mis Solicitudes y **el emisor no se entera de nada**.
  final VoidCallback? onIgnore;

  final VoidCallback? onBlock;
  final VoidCallback? onReport;

  /// Mientras una acción está en vuelo. Las cuatro son de un solo uso: dos toques seguidos en
  /// `Aceptar` mandarían dos `accept` sobre la misma conversación.
  final bool busy;

  @override
  Widget build(BuildContext context) {
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
            AppSpacing.md - 2,
            AppSpacing.md,
            AppSpacing.sm,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: _Principal(
                      itemKey: acceptKey,
                      label: accept,
                      onPressed: busy ? null : onAccept,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: _Secundario(
                      itemKey: ignoreKey,
                      label: ignore,
                      onPressed: busy ? null : onIgnore,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: <Widget>[
                  Expanded(
                    child: _Secundario(
                      itemKey: blockKey,
                      label: block,
                      danger: true,
                      onPressed: busy ? null : onBlock,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: _Secundario(
                      itemKey: reportKey,
                      label: report,
                      danger: true,
                      onPressed: busy ? null : onReport,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Principal extends StatelessWidget {
  const _Principal({
    required this.itemKey,
    required this.label,
    required this.onPressed,
  });

  final Key itemKey;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => FilledButton(
    key: itemKey,
    onPressed: onPressed,
    style: FilledButton.styleFrom(
      backgroundColor: context.palette.brandStrong,
      foregroundColor: context.palette.onBrand,
      minimumSize: const Size.fromHeight(46),
    ),
    child: Text(label),
  );
}

class _Secundario extends StatelessWidget {
  const _Secundario({
    required this.itemKey,
    required this.label,
    required this.onPressed,
    this.danger = false,
  });

  final Key itemKey;
  final String label;
  final VoidCallback? onPressed;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final bool apagado = onPressed == null;
    return OutlinedButton(
      key: itemKey,
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: danger ? context.palette.error : context.palette.brandStrong,
        // El borde se apaga CON el botón. Con un `BorderSide` fijo, `Bloquear` y `Reportar`
        // conservaban su marco rojo estando muertos: se leían como armados y peligrosos, cuando lo
        // único que hacen hoy es nada. Se vio en el emulador.
        side: BorderSide(
          color: apagado
              ? context.palette.outline
              : (danger ? context.palette.error : context.palette.chip),
        ),
        minimumSize: const Size.fromHeight(46),
      ),
      child: Text(label),
    );
  }
}
