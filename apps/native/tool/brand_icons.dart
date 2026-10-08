import 'dart:io';
import 'package:image/image.dart' as image;

void main(List<String> arguments) {
  if (arguments.any((value) => value != '--ios-only')) {
    throw ArgumentError('Usage: dart run tool/brand_icons.dart [--ios-only]');
  }
  final logo = image.decodePng(File('assets/logo.png').readAsBytesSync())!;
  if (!arguments.contains('--ios-only')) {
    final ico = image.IcoEncoder().encodeImages([
      for (final size in [16, 24, 32, 48, 64, 128, 256])
        image.copyResize(logo, width: size, height: size),
    ]);
    File('assets/app_icon.ico').writeAsBytesSync(ico);
    File('windows/runner/resources/app_icon.ico').writeAsBytesSync(ico);
    for (final item in {
      'mdpi': 48,
      'hdpi': 72,
      'xhdpi': 96,
      'xxhdpi': 144,
      'xxxhdpi': 192,
    }.entries) {
      File(
        'android/app/src/main/res/mipmap-${item.key}/ic_launcher.png',
      ).writeAsBytesSync(
        image.encodePng(
          image.copyResize(logo, width: item.value, height: item.value),
        ),
      );
    }
  }
  final iosDirectory = Directory(
    'ios/Runner/Assets.xcassets/AppIcon.appiconset',
  );
  final sizes = {
    '20x20@1x': 20,
    '20x20@2x': 40,
    '20x20@3x': 60,
    '29x29@1x': 29,
    '29x29@2x': 58,
    '29x29@3x': 87,
    '40x40@1x': 40,
    '40x40@2x': 80,
    '40x40@3x': 120,
    '60x60@2x': 120,
    '60x60@3x': 180,
    '76x76@1x': 76,
    '76x76@2x': 152,
    '83.5x83.5@2x': 167,
    '1024x1024@1x': 1024,
  };
  for (final entry in sizes.entries) {
    // App Store icons must be opaque. Preserve the same mark on its cream base.
    final canvas = image.Image(
      width: entry.value,
      height: entry.value,
      numChannels: 3,
    );
    image.fill(canvas, color: image.ColorRgb8(0xef, 0xed, 0xe3));
    image.compositeImage(
      canvas,
      image.copyResize(logo, width: entry.value, height: entry.value),
    );
    File(
      '${iosDirectory.path}/Icon-App-${entry.key}.png',
    ).writeAsBytesSync(image.encodePng(canvas));
  }
  stdout.writeln(
    'Exported ${sizes.length} opaque iOS icons'
    '${arguments.contains('--ios-only') ? '' : ' and Android/Windows icons'}.',
  );
}
