import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'studio31.dart';
import 'widgets.dart';

Future<String?> cropProfileFile(
  BuildContext context,
  String path,
  String kind,
) async {
  final bytes = await File(path).readAsBytes();
  if (bytes.length > 8 * 1024 * 1024) {
    throw const FormatException('Image is larger than 8 MB');
  }
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  final descriptor = await ui.ImageDescriptor.encoded(buffer);
  final oversized =
      descriptor.width > 16384 ||
      descriptor.height > 16384 ||
      descriptor.width * descriptor.height > 40000000;
  descriptor.dispose();
  buffer.dispose();
  if (oversized) throw const FormatException('Image dimensions are too large');
  final animated =
      path.toLowerCase().endsWith('.gif') ||
      String.fromCharCodes(bytes.take(300)).contains('ANIM') ||
      String.fromCharCodes(bytes.take(500)).contains('acTL');
  if (animated) {
    if (!context.mounted) return null;
    final keep = await showWaveDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(
          Localizations.localeOf(context).languageCode == 'ru'
              ? 'Анимированное изображение'
              : 'Animated image',
        ),
        content: Text(
          Localizations.localeOf(context).languageCode == 'ru'
              ? 'Можно сохранить исходную анимацию или обрезать один кадр.'
              : 'Keep the animation or crop a single frame.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: Text(studioText(context, 'cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: Text(
              Localizations.localeOf(context).languageCode == 'ru'
                  ? 'Обрезать кадр'
                  : 'Crop frame',
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: Text(
              Localizations.localeOf(context).languageCode == 'ru'
                  ? 'Сохранить анимацию'
                  : 'Keep animation',
            ),
          ),
        ],
      ),
    );
    if (keep == null) return null;
    if (keep) return path;
  }
  final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: 2048,
        allowUpscaling: false,
      ),
      frame = await codec.getNextFrame();
  codec.dispose();
  if (!context.mounted) {
    frame.image.dispose();
    return null;
  }
  final result = await showWaveDialog<Uint8List>(
    context: context,
    builder: (_) =>
        ProfileCropDialog(image: frame.image, avatar: kind == 'avatar'),
  );
  frame.image.dispose();
  if (result == null) return null;
  final folder = await Directory.systemTemp.createTemp('glukwave-crop-');
  final file = File('${folder.path}/crop.png');
  await file.writeAsBytes(result);
  return file.path;
}

class ProfileCropDialog extends StatefulWidget {
  final ui.Image image;
  final bool avatar;
  const ProfileCropDialog({
    super.key,
    required this.image,
    required this.avatar,
  });
  @override
  State<ProfileCropDialog> createState() => _ProfileCropDialogState();
}

class _ProfileCropDialogState extends State<ProfileCropDialog> {
  double zoom = 1;
  Offset pan = Offset.zero;
  Size viewport = Size.zero;
  bool saving = false;
  double get aspect => widget.avatar ? 1 : 3;
  double get scale => viewport.isEmpty
      ? 1
      : (viewport.width / widget.image.width).clamp(
              viewport.height / widget.image.height,
              double.infinity,
            ) *
            zoom;
  Offset get offset {
    final width = widget.image.width * scale,
        height = widget.image.height * scale;
    return Offset(
      ((viewport.width - width) / 2 + pan.dx).clamp(viewport.width - width, 0),
      ((viewport.height - height) / 2 + pan.dy).clamp(
        viewport.height - height,
        0,
      ),
    );
  }

  Future<void> save() async {
    setState(() => saving = true);
    try {
      final width = widget.avatar ? 640 : 1600,
          height = (width / aspect).round(),
          ratio = width / viewport.width,
          record = ui.PictureRecorder(),
          canvas = Canvas(record);
      canvas.scale(ratio);
      canvas.translate(offset.dx, offset.dy);
      canvas.scale(scale);
      canvas.drawImage(
        widget.image,
        Offset.zero,
        Paint()..filterQuality = FilterQuality.high,
      );
      final image = await record.endRecording().toImage(width, height),
          data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (mounted) Navigator.pop(context, data!.buffer.asUint8List());
    } catch (_) {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ru = Localizations.localeOf(context).languageCode == 'ru',
        v = waveVisuals(context);
    final cropWidth =
        ((MediaQuery.sizeOf(context).height - 320).clamp(120, 440) * aspect)
            .clamp(120, 440)
            .clamp(1, MediaQuery.sizeOf(context).width - 96)
            .toDouble();
    return AlertDialog(
      key: const Key('profile-crop-dialog'),
      scrollable: true,
      title: Text(
        ru
            ? (widget.avatar ? 'Обрезать аватар' : 'Обрезать баннер')
            : (widget.avatar ? 'Crop avatar' : 'Crop banner'),
      ),
      content: SizedBox(
        width: cropWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              ru
                  ? 'Перемести изображение и выбери масштаб.'
                  : 'Move the image and choose the zoom.',
              style: TextStyle(color: v.muted, fontSize: 12),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: cropWidth,
              height: cropWidth / aspect,
              child: LayoutBuilder(
                builder: (_, constraints) {
                  viewport = constraints.biggest;
                  return ClipRect(
                    child: GestureDetector(
                      key: const Key('profile-crop-image'),
                      onPanUpdate: saving
                          ? null
                          : (e) => setState(() => pan += e.delta),
                      child: CustomPaint(
                        painter: _CropPreview(
                          widget.image,
                          offset,
                          scale,
                          widget.avatar,
                        ),
                        size: viewport,
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 14),
            Slider(
              key: const Key('profile-crop-zoom'),
              value: zoom,
              min: 1,
              max: 4,
              onChanged: saving
                  ? null
                  : (value) => setState(() => zoom = value),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: saving ? null : () => Navigator.pop(context),
          child: Text(studioText(context, 'cancel')),
        ),
        FilledButton(
          onPressed: saving ? null : save,
          child: Text(saving ? '…' : studioText(context, 'done')),
        ),
      ],
    );
  }
}

class _CropPreview extends CustomPainter {
  final ui.Image image;
  final Offset offset;
  final double scale;
  final bool avatar;
  const _CropPreview(this.image, this.offset, this.scale, this.avatar);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    canvas.scale(scale);
    canvas.drawImage(
      image,
      Offset.zero,
      Paint()..filterQuality = FilterQuality.medium,
    );
    canvas.restore();
    if (avatar) {
      final path = Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(Offset.zero & size)
        ..addOval(
          Rect.fromCircle(
            center: size.center(Offset.zero),
            radius: size.width / 2,
          ),
        );
      canvas.drawPath(
        path,
        Paint()..color = Colors.black.withValues(alpha: .4),
      );
    }
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white54,
    );
  }

  @override
  bool shouldRepaint(_CropPreview old) =>
      old.offset != offset || old.scale != scale || old.image != image;
}
