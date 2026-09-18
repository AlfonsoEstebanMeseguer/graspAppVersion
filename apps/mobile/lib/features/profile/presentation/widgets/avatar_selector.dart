import 'package:flutter/material.dart';

import '../../../../core/theming/grasp_palette.dart';
import '../../../../core/theming/app_theme.dart';
import '../../../../domain/profile/avatar_type.dart';

/// Selector de avatar: muestra una grilla 2×4 de avatares estáticos
/// donde el usuario puede seleccionar uno.
///
/// Emite el avatar seleccionado a través del callback [onSelected].
/// Opcionalmente puede inicializarse con un avatar preseleccionado.
class AvatarSelector extends StatefulWidget {
  const AvatarSelector({
    super.key,
    required this.onSelected,
    this.selectedAvatar,
  });

  /// Callback invocado cuando el usuario selecciona un avatar.
  final Function(AvatarType) onSelected;

  /// Avatar preseleccionado. Si es `null`, se inicializa en [AvatarType.gym].
  final AvatarType? selectedAvatar;

  @override
  State<AvatarSelector> createState() => _AvatarSelectorState();
}

class _AvatarSelectorState extends State<AvatarSelector> {
  late AvatarType _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.selectedAvatar ?? AvatarType.gym;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.gutter,
              vertical: AppSpacing.md,
            ),
            child: Text(
              'Elige tu avatar',
              style: theme.textTheme.titleLarge,
            ),
          ),
          GridView.count(
            crossAxisCount: 2,
            childAspectRatio: 1,
            mainAxisSpacing: AppSpacing.md,
            crossAxisSpacing: AppSpacing.md,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: <Widget>[
              for (final AvatarType avatar in AvatarType.values)
                _AvatarCard(
                  avatar: avatar,
                  isSelected: _selected == avatar,
                  onTap: () {
                    setState(() => _selected = avatar);
                    widget.onSelected(avatar);
                  },
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
        ],
      ),
    );
  }
}

/// Card individual para un avatar: muestra la imagen y el label,
/// con borde que cambia de color y grosor al ser seleccionado.
class _AvatarCard extends StatelessWidget {
  const _AvatarCard({
    required this.avatar,
    required this.isSelected,
    required this.onTap,
  });

  final AvatarType avatar;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(
            color: isSelected ? context.palette.brandStrong : context.palette.outline,
            width: isSelected ? 3 : 1,
          ),
          borderRadius: BorderRadius.circular(AppSpacing.sm),
          color: context.palette.surface,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Image.asset(
              avatar.assetPath,
              width: 80,
              height: 80,
              fit: BoxFit.contain,
              errorBuilder: (BuildContext context, Object error, StackTrace? st) {
                return Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: context.palette.containerSubtle,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.image_not_supported_outlined,
                    color: context.palette.iconSoft,
                  ),
                );
              },
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              avatar.label,
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
