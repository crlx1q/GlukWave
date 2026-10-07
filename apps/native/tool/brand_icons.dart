import 'dart:io';
import 'package:image/image.dart' as image;

void main() {
  final logo = image.decodePng(File('assets/logo.png').readAsBytesSync())!;
  final ico = image.encodeIco(image.copyResize(logo, width: 256, height: 256));
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
    File('${iosDirectory.path}/Icon-App-${entry.key}.png').writeAsBytesSync(
      image.encodePng(
        image.copyResize(logo, width: entry.value, height: entry.value),
      ),
    );
  }
}
