# GlukWave

Gluk Wave — Flutter музыкальное приложение с персональной волной, Lo-fi режимом и SoundCloud.

## Возможности

- Персональная «волна» в реальном времени на экране плеера
- Lo-fi режим для более мягкого звукового профиля
- Каталог треков на русском языке
- Интеграционная точка для SoundCloud ссылок

## Структура

- `lib/models.dart`
- `lib/theme.dart`
- `lib/data.dart`
- `lib/synth.dart`
- `lib/soundcloud.dart`
- `lib/cover_art.dart`
- `lib/wave_hero.dart`
- `lib/app_state.dart`
- `lib/main.dart`
- `lib/widgets/`
- `lib/screens/`

## Локальный запуск

```bash
flutter pub get
flutter run
```

## CI сборка APK

Workflow: `.github/workflows/build-apk.yml`

Выполняет:
1. checkout репозитория
2. setup Flutter
3. `flutter pub get`
4. `flutter build apk --release`
5. upload `build/app/outputs/flutter-apk/app-release.apk` как artifact `glukwave-apk`
