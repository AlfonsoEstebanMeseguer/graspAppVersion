import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/theming/grasp_palette.dart';
import '../../../../core/theming/app_theme.dart';
import '../../../../domain/profile/avatar_type.dart';
import '../../application/avatar_controller.dart';
import 'avatar_crop_sheet.dart';
import 'avatar_selector.dart';

/// Elige la foto del carrete. Se inyecta para poder probar la hoja sin abrir el selector del
/// sistema, que en un test no existe.
typedef PickImageBytes = Future<Uint8List?> Function();

Future<Uint8List?> _pickFromGallery() async {
  final XFile? file = await ImagePicker().pickImage(
    source: ImageSource.gallery,
    // El recorte de tamaño de verdad lo hace `prepareAvatarUpload`; esto solo evita cargar en
    // memoria una foto de 12 MP para tirarla acto seguido.
    maxWidth: 2048,
    maxHeight: 2048,
  );
  // `readAsBytes` y no `path`: en web el `path` es una URL de blob, no un fichero.
  return file == null ? null : await file.readAsBytes();
}

/// Hoja modal para cambiar el avatar — la decisión 0014.
///
/// Dos acciones y no tres: **no hay «quitar la foto»** porque el backend exige exactamente uno de
/// `photo_path` o `preset`, y quitarse la foto se hace eligiendo un dibujo (que además la encola
/// para borrarla de R2). Ver la corrección al final de la decisión 0014.
///
/// No es una pantalla con ruta propia a propósito: elegir avatar es una acción de dos toques que
/// empieza y acaba mirando el perfil, y sacarla a una ruta alejaría al usuario del sitio donde se
/// ve el resultado.
class AvatarSheet extends ConsumerStatefulWidget {
  const AvatarSheet({
    super.key,
    this.selected,
    this.pickImage,
    this.skipCrop = false,
  });

  /// Avatar predeterminado actual, si lo hay, para preseleccionarlo en la grilla.
  final AvatarType? selected;

  /// Sustituible en tests. En producción abre el selector del sistema.
  final PickImageBytes? pickImage;

  /// Salta el paso de recorte. Solo para tests: recortar necesita decodificar una imagen de
  /// verdad, y los tests de esta hoja van sobre el flujo, no sobre el encuadre (que tiene los
  /// suyos en `crop_geometry_test.dart`).
  final bool skipCrop;

  static Future<void> show(
    BuildContext context, {
    AvatarType? selected,
    PickImageBytes? pickImage,
    bool skipCrop = false,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.palette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.sheet),
        ),
      ),
      builder: (BuildContext context) => AvatarSheet(
        selected: selected,
        pickImage: pickImage,
        skipCrop: skipCrop,
      ),
    );
  }

  @override
  ConsumerState<AvatarSheet> createState() => _AvatarSheetState();
}

class _AvatarSheetState extends ConsumerState<AvatarSheet> {
  bool _choosingPreset = false;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AsyncValue<void> operation = ref.watch(avatarControllerProvider);
    final bool busy = operation.isLoading;

    return SafeArea(
      child: ConstrainedBox(
        // La grilla de 8 avatares no cabe en una hoja que se ajuste a su contenido: sin este tope
        // desborda por cientos de píxeles en cuanto se abre. Se limita a 4/5 de pantalla y la
        // grilla cede el espacio sobrante (`Flexible` más abajo), que es lo que la hace scrollable.
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.gutter,
            vertical: AppSpacing.md,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                _choosingPreset ? 'Elige tu avatar' : 'Foto de perfil',
                style: theme.textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.md),

              if (operation.hasError) ...<Widget>[
                // El error se enseña DENTRO de la hoja: cerrarla obligaría a rehacer todo el
                // recorrido solo para reintentar.
                Container(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: context.palette.containerSubtle,
                    borderRadius: BorderRadius.circular(AppRadius.field),
                  ),
                  child: Text(
                    operation.error.toString(),
                    style: theme.textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
              ],

              if (_choosingPreset)
                // `Flexible` y no un hijo suelto: el `SingleChildScrollView` que ya lleva dentro
                // `AvatarSelector` solo puede desplazarse si recibe una altura acotada.
                Flexible(
                  child: AvatarSelector(
                    selectedAvatar: widget.selected,
                    onSelected: busy ? (AvatarType _) {} : _onPresetSelected,
                  ),
                )
              else ...<Widget>[
                _SheetAction(
                  icon: Icons.face_retouching_natural_rounded,
                  label: 'Elegir un avatar',
                  onTap: busy
                      ? null
                      : () => setState(() => _choosingPreset = true),
                ),
                const SizedBox(height: AppSpacing.sm),
                _SheetAction(
                  icon: Icons.photo_library_rounded,
                  label: 'Subir una foto',
                  onTap: busy ? null : _onUploadPhoto,
                ),
              ],

              if (busy) ...<Widget>[
                const SizedBox(height: AppSpacing.md),
                const Center(child: CircularProgressIndicator()),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _onPresetSelected(AvatarType preset) async {
    final bool ok = await ref
        .read(avatarControllerProvider.notifier)
        .setPreset(preset);
    if (ok && mounted) Navigator.of(context).pop();
  }

  Future<void> _onUploadPhoto() async {
    final PickImageBytes pick = widget.pickImage ?? _pickFromGallery;
    final Uint8List? picked = await pick();
    if (picked == null) return; // el usuario canceló: no es un error
    if (!mounted) return;

    // Ajustar el encuadre ANTES de comprimir. Si se recortara después, se estaría recortando una
    // imagen ya degradada, y el zoom ampliaría los defectos de la compresión.
    final Uint8List? cropped = widget.skipCrop
        ? picked
        : await AvatarCropSheet.show(context, picked);
    if (cropped == null) return; // canceló el recorte: tampoco es un error
    if (!mounted) return;

    final bool ok = await ref
        .read(avatarControllerProvider.notifier)
        .uploadPhoto(cropped);
    if (ok && mounted) Navigator.of(context).pop();
  }
}

class _SheetAction extends StatelessWidget {
  const _SheetAction({required this.icon, required this.label, this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      child: Material(
        color: context.palette.containerSubtle,
        borderRadius: BorderRadius.circular(AppRadius.field),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.field),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.md,
            ),
            child: Row(
              children: <Widget>[
                Icon(icon, color: context.palette.brandStrong),
                const SizedBox(width: AppSpacing.sm),
                Text(label, style: theme.textTheme.bodyLarge),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
