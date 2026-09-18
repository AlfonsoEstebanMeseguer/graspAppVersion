import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../../core/theming/grasp_palette.dart';
import '../../../../core/theming/app_theme.dart';
import '../../../../core/ui/grasp_buttons.dart';
import '../../../../data/profile/crop_geometry.dart';

/// Lado del recorte que se sube. 512 da margen para pantallas densas sin acercarse a los 200 KB.
const int _outputSide = 512;

/// Cuánto scroll de rueda hace falta por unidad de zoom. Más alto = más progresivo.
const double _wheelScaleFactor = 1000;

/// Ajustar el encuadre antes de subir: mover y hacer zoom dentro de un círculo.
///
/// POR QUÉ NO SE USA `image_cropper`
///
/// Ese paquete envuelve una librería nativa distinta en cada plataforma, así que la pantalla que ve
/// la persona cambia según el móvil; en web además exige meter JavaScript de terceros en
/// `index.html`. Esto son cien líneas de Flutter que se ven igual en todas partes, respetan los
/// tokens de Grasp y no añaden configuración nativa. La parte que podía fallar en silencio —pasar
/// del gesto a los píxeles— está en `data/profile/crop_geometry.dart`, con sus tests.
///
/// Devuelve los bytes **PNG** del recorte, o `null` si se cancela. PNG y no WebP a propósito: aquí
/// solo se recorta, y quien decide el formato final es el compresor (decisión 0012), que es el
/// único que sabe qué sabe producir esta plataforma.
class AvatarCropSheet extends StatefulWidget {
  const AvatarCropSheet({super.key, required this.imageBytes});

  final Uint8List imageBytes;

  static Future<Uint8List?> show(BuildContext context, Uint8List imageBytes) {
    return showModalBottomSheet<Uint8List?>(
      context: context,
      isScrollControlled: true,
      // LOS DOS GESTOS DE CIERRE SE APAGAN, Y NO ES UNA MANÍA DE DISEÑO.
      //
      // Una hoja modal se cierra arrastrándola hacia abajo, y ese gesto es **el mismo** que ajustar
      // el encuadre: al mover la foto hacia abajo, la hoja se lo quedaba y se cerraba a medio
      // encuadrar. Con dos cosas arrastrables una encima de otra, gana la de fuera, así que la de
      // fuera tiene que dejar de escuchar.
      //
      // `isDismissible: false` va con ello por coherencia: si arrastrar ya no cierra, tocar fuera
      // tampoco debería, o el mismo trabajo se pierde de dos formas distintas. La salida es el
      // botón «Cancelar», que además es explícito — aquí hay trabajo a medias que se descarta.
      enableDrag: false,
      isDismissible: false,
      backgroundColor: context.palette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
      ),
      builder: (BuildContext context) => AvatarCropSheet(imageBytes: imageBytes),
    );
  }

  @override
  State<AvatarCropSheet> createState() => _AvatarCropSheetState();
}

class _AvatarCropSheetState extends State<AvatarCropSheet> {
  final TransformationController _controller = TransformationController();
  ui.Image? _image;
  bool _working = false;
  String? _error;

  /// Lado de la ventana de recorte, medido en el `LayoutBuilder`. `_renderCrop` lo necesita para
  /// reconstruir exactamente la misma geometría que la persona vio.
  double _side = 320;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  @override
  void dispose() {
    _controller.dispose();
    _image?.dispose();
    super.dispose();
  }

  Future<void> _decode() async {
    try {
      final ui.Codec codec = await ui.instantiateImageCodec(widget.imageBytes);
      final ui.FrameInfo frame = await codec.getNextFrame();
      if (mounted) setState(() => _image = frame.image);
    } on Object {
      if (mounted) {
        setState(() => _error = 'No se pudo abrir esa imagen. Prueba con otra.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ui.Image? image = _image;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.gutter,
          vertical: AppSpacing.md,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text('Ajusta tu foto', style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Arrastra para mover y pellizca para acercar.',
              style: theme.textTheme.bodySmall?.copyWith(color: context.palette.textMuted),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.md),

            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                child: Text(_error!, style: theme.textTheme.bodyMedium),
              )
            else if (image == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
                child: CircularProgressIndicator(),
              )
            else
              LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  // Cuadrado, y nunca más ancho que la pantalla ni más alto que media.
                  final double side = constraints.maxWidth.clamp(0.0, 320.0);
                  final Size child = coverSize(
                    imageSize: Size(image.width.toDouble(), image.height.toDouble()),
                    viewportSide: side,
                  );
                  // El lado real solo se conoce al medir, y `_renderCrop` lo necesita para
                  // reconstruir la misma geometría que se vio.
                  _side = side;
                  return _CropWindow(
                    side: side,
                    childSize: child,
                    controller: _controller,
                    image: image,
                  );
                },
              ),

            const SizedBox(height: AppSpacing.md),
            Row(
              children: <Widget>[
                Expanded(
                  child: GraspSecondaryButton(
                    label: 'Cancelar',
                    onPressed: _working
                        ? null
                        : () => Navigator.of(context).pop(),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: GraspPrimaryButton(
                    label: 'Usar esta foto',
                    onPressed: (image == null || _working) ? null : _confirm,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirm() async {
    final ui.Image? image = _image;
    if (image == null) return;
    setState(() => _working = true);

    try {
      final Uint8List bytes = await _renderCrop(image);
      if (mounted) Navigator.of(context).pop(bytes);
    } on Object {
      if (mounted) {
        setState(() {
          _working = false;
          _error = 'No se pudo recortar la imagen. Prueba con otra.';
        });
      }
    }
  }

  /// Pinta el trozo elegido en un lienzo de 512×512 y devuelve sus bytes PNG.
  Future<Uint8List> _renderCrop(ui.Image image) async {
    final double side = _side;
    final Size childSize = coverSize(
      imageSize: Size(image.width.toDouble(), image.height.toDouble()),
      viewportSide: side,
    );
    final Rect src = computeCropRect(
      matrix: _controller.value,
      viewportSide: side,
      childSize: childSize,
      imageSize: Size(image.width.toDouble(), image.height.toDouble()),
    );

    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder);
    canvas.drawImageRect(
      image,
      src,
      const Rect.fromLTWH(0, 0, _outputSide * 1.0, _outputSide * 1.0),
      Paint()..filterQuality = FilterQuality.high,
    );
    final ui.Image cropped = await recorder.endRecording().toImage(
      _outputSide,
      _outputSide,
    );
    final ByteData? data = await cropped.toByteData(
      format: ui.ImageByteFormat.png,
    );
    cropped.dispose();

    if (data == null) {
      throw StateError('El recorte no produjo bytes');
    }
    return data.buffer.asUint8List();
  }

}

class _CropWindow extends StatelessWidget {
  const _CropWindow({
    required this.side,
    required this.childSize,
    required this.controller,
    required this.image,
  });

  final double side;
  final Size childSize;
  final TransformationController controller;
  final ui.Image image;

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: SizedBox(
        width: side,
        height: side,
        child: InteractiveViewer(
          transformationController: controller,
          minScale: 1,
          maxScale: 5,
          // Por defecto son 200, y con eso cada muesca de rueda salta casi un 40%
          // (`exp(-scrollDelta / scaleFactor)`): el encuadre se pasa de largo y hay que
          // corregirlo. Subirlo lo deja en torno al 10% por muesca.
          scaleFactor: _wheelScaleFactor,
          // Sin límites: el recorte ya se acota contra la imagen en `computeCropRect`, y
          // restringir aquí haría que el gesto se sintiera pegajoso en los bordes.
          constrained: false,
          child: SizedBox(
            width: childSize.width,
            height: childSize.height,
            child: RawImage(
              image: image,
              width: childSize.width,
              height: childSize.height,
              fit: BoxFit.fill,
            ),
          ),
        ),
      ),
    );
  }
}
