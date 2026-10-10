# Компоненты, материалы и лицензии

Итерация 1.0.0+5 использует независимо установленные серверные yt-dlp/yt-dlp-ejs, ytmusicapi, spotDL и Deno; исходники и лицензии: https://github.com/yt-dlp/yt-dlp, https://github.com/yt-dlp/ejs, https://github.com/sigma67/ytmusicapi, https://github.com/spotDL/spotify-downloader, https://github.com/denoland/deno. Они не включены в клиентские APK/EXE. Условия зависимостей и лицензии медиа действуют отдельно; правила собственных разрешённых потоков описаны в PERMITTED-AUDIO.md.

Основой оформления служит предоставленный пользователем `Gluk-Wave-v2.html`; `Gluk-Wave-v6-PC-fixed.html` уточняет мобильную компоновку и жесты. Неизменённые копии макетов входят в `docs/design-reference` для дальнейшей разработки. Файлы в `Downloads\d` не изменялись. Готовые пользовательские каталоги, чужие профили и демонстрационная музыка из макета в сервис не перенесены.

## Originkit

Волна Bloom адаптирована из **Halftone Bloom**: [Originkit](https://www.originkit.dev/). Компонент действительно получен командой официального CLI `originkit@0.2.25 add halftone-bloom --prompt` с авторизацией владельца; исходный компонент использует WebGL2 и два прохода шейдера. В GlukWave поле преобразовано в ленту, добавлена измеренная реакция на музыку, курсор/касание и настройки оформления. Flutter-перенос использует те же уравнения формы.

CLI приобрёл компонент во временную рабочую папку; ключ авторизации не включён в код клиента, Flutter-сборку, документацию или архив. MIT-лицензия npm-пакета CLI относится к CLI, её не следует выдавать за отдельную лицензию полученного компонента. При дальнейшей перепубликации компонента отдельно от проекта проверьте условия Originkit для вашего аккаунта.

## Morphicons

Анимированные иконки: [Morphicons](https://www.morphicons.com/), Guillermo López. Используется пакет `morphicons`, MIT. Полный текст сохранён в [licenses/Morphicons-MIT.txt](licenses/Morphicons-MIT.txt). Иконки учитывают пользовательское отключение анимации; никакого ключа сервиса для их работы не требуется.

## Skiper UI

Изучен [каталог Skiper UI](https://skiper-ui.com/components): варианты взаимодействий, переключатели темы, музыкальные кнопки, progressive blur и squircle. Реализация GlukWave сохраняет собственные стили и исходный макет. Платные компоненты не извлекались и не включались. Если при дальнейшей работе добавляется код бесплатного компонента, необходимо сохранить требуемое Skiper UI указание авторства; установка пакета сама по себе не даёт доступ к Pro-компонентам.

## Шрифты и обработка звука

Nunito: SIL Open Font License, текст в `docs/licenses` и в составе Flutter-ресурсов. Во Flutter зарегистрированы шесть настоящих статических начертаний 400–900, полученных из исходного variable-font Nunito с сохранением покрытия символов и уведомлений об авторстве. Воспроизводимый генератор — `apps/native/tool/instantiate_fonts.py`; он требует fontTools и не запускается при обычной сборке приложения.

Сервер использует `ffmpeg-static` для анализа загруженного аудио. Дистрибутив FFmpeg имеет собственную GPL-лицензию; полный текст пакета сохранён в [licenses/FFmpeg-static-GPL.txt](licenses/FFmpeg-static-GPL.txt). npm-пакет предоставляет исполняемый файл для текущей ОС, исходники FFmpeg и инструкции доступны в [официальном проекте](https://ffmpeg.org/). Архив исходников GlukWave не содержит `node_modules` и отдельно не распространяет этот исполняемый файл. При распространении собственного образа/бинарной поставки сохраните уведомления и выполните обязательства именно выбранной сборки FFmpeg.

Остальные сторонние зависимости перечислены в `package-lock.json` и `apps/native/pubspec.lock`; Flutter показывает зарегистрированные лицензии стандартным экраном приложения.

## Обновление макетов v7 и шрифт Manrope

Потоковая волна по умолчанию переработана по предоставленному владельцем `index(3).html`. Компоновка и жесты уточнены по `Gluk Wave v7.html` и видео; `miyux-ideal-standalone.html` использован как визуальный ориентир профиля. Чужие профили, имена и музыкальный каталог из примеров не включены. Bloom остаётся отдельным стилем со своим происхождением.

Manrope: [официальный каталог Google Fonts](https://github.com/google/fonts/tree/main/ofl/manrope), SIL Open Font License. Локальная веб-версия WOFF2 содержит ось веса 200–800; для Flutter подготовлены статические начертания 400–800. Уведомление сохранено в `apps/web/public/brand/Manrope-OFL.txt` и `apps/native/assets/licenses/Manrope-OFL.txt`. Для казахских символов, отсутствующих в Manrope, используется установленный локальный Nunito. Обе гарнитуры работают без запросов к внешнему серверу шрифтов.

## База стран IP

Для автоматического выбора языка используется локальная база **user-country** от [sapics/ip-location-db](https://github.com/sapics/ip-location-db), опубликованная под [PDDL1.0](https://opendatacommons.org/licenses/pddl/1-0/). IPv4/IPv6 CSV преобразованы в проверенные отсортированные диапазоны и gzip без изменения стран. Исходные и итоговые SHA-256, дата получения и число диапазонов сохранены в `apps/server/data/geoip/provenance.json`. Это страна сети, без координат/города; адрес посетителя не отправляется геосервису. Точный источник и способ обновления описаны рядом с базой.

## LRCLIB

Тексты загружаются во время использования из [LRCLIB](https://lrclib.net/docs), с указанием источника в метаданных. Они не включены в код, APK или Windows-пакет; общедоступность записи не означает передачу авторских прав на сам текст. Программная реализация клиента написана внутри GlukWave. Синхронизированный текст доступен только при наличии подходящей записи в каталоге.

## Windows audio runtime

`just_audio_media_kit` / `media_kit` use MIT-licensed Dart/plugin wrappers. The separate bundled `libmpv-2.dll` is **not MIT**. `media_kit_libs_windows_audio 1.0.9` downloads the upstream [2023-09-24 audio build](https://github.com/media-kit/libmpv-win32-audio-build/releases/tag/2023-09-24), archive `mpv-dev-x86_64-20230924-git-652a1dd.7z`, MD5 `cd738e16e2a19626d7cfa48801524f8c` as required by that package. It is dynamically loaded; it can be replaced independently of the application.

The [mpv source at the embedded revision](https://github.com/mpv-player/mpv/tree/652a1dd), [audio build scripts](https://github.com/media-kit/libmpv-win32-audio-build), and [FFmpeg sources](https://github.com/FFmpeg/FFmpeg) are available upstream. The audio build scripts select `gpl=false` for mpv and `--disable-gpl --disable-nonfree --enable-version3` for FFmpeg. Full mpv copyright, GPL/LGPL and FFmpeg LGPL notices are preserved in `docs/licenses` and copied beside the Windows executable. The exact dependency source revisions and a reproducible source bundle still need a separate distribution audit before a public release; this local test package is not presented as a completed public distribution.

The Windows folder also includes unmodified Microsoft Visual C++ CRT DLLs from the installed Build Tools redistributable directory. Microsoft retains their copyright; the [Visual Studio redistribution list and terms](https://learn.microsoft.com/en-us/visualstudio/releases/2022/redistribution) apply. They are neither GlukWave source nor covered by the plugin MIT licenses. The Windows ZIP is a portable local beta and is not Authenticode signed.

## Client update 1.0.0+3

The Google sign-in G is the unmodified [official asset](https://developers.google.com/static/identity/images/g-logo.png), displayed according to the [Google branding guide](https://developers.google.com/identity/branding-guidelines), with a white backing. It is a Google trademark, not a GlukWave icon.

Lyrics lookup uses the public [LRCLIB API](https://lrclib.net/docs) and the fixed-host [lyrics.ovh service](https://github.com/NTag/lyrics.ovh) as a plain-text fallback. The provider service does not guarantee coverage. Track metadata and record length determine whether timed lyrics are safe to attach; users' saved lyrics take priority.

The Windows installer is compiled with unmodified [Inno Setup](https://jrsoftware.org/isinfo.php) 6.7.3. Copyright (C) 1997–2026 Jordan Russell; portions Copyright (C) 2000–2026 Martijn Laan. Its original license is included in `docs/licenses/Inno-Setup.txt` and in the Windows bundle. The build uses a portable compiler and does not install developer tooling on the user's machine. The installer and application remain unsigned beta packages.

## Official provider players in Flutter

The Windows music DSP adapter in `apps/native/lib/services/windows_mpv_player.dart` is adapted from Pato05's `just_audio_media_kit` 2.1.0 `mediakit_player.dart`. The upstream implementation is public-domain software under the Unlicense; its full original text ships as `apps/native/assets/licenses/just_audio_media_kit-UNLICENSE.txt` and appears in the native licenses screen. GlukWave adds a checked mpv `af` bridge for ten lavfi equalizer bands, preceded by native float conversion because the pinned runtime omits FFmpeg resampling/volume filters. Preamp uses mpv software volume; matching the active music URI excludes the separate rain output. Rejected properties restore normal filters and volume. The existing media-kit/libmpv licenses and distribution obligations above still apply. A generated WAV passed the bundled DLL with null audio output; this and property-boundary tests do not establish physical Windows audio verification.

The Flutter clients use flutter_inappwebview 6.1.5 (Apache-2.0). Its original license is preserved in docs/licenses/InAppWebView-Apache-2.0.txt and the Windows bundle. Windows uses Microsoft WebView2; the installer bundles Microsoft's signed Evergreen bootstrapper, which obtains the runtime from Microsoft when absent. The player remains visible and source media stays inside official SoundCloud/YouTube embeds. No extracted audio stream or provider account credential is included.

Windows developer builds need NuGet, as documented by [InAppWebView](https://inappwebview.dev/docs/intro/#setup-windows) and [Microsoft](https://learn.microsoft.com/en-us/nuget/install-nuget-client-tools). scripts/prepare-nuget.ps1 obtains and verifies the Microsoft-signed tool; it is build tooling and is not included in the application.


Discord protocol research (10 October 2026): official Social SDK/OAuth documentation, Neurobox repository (AGPL-3.0) and PreMiD repository were consulted. No Neurobox/PreMiD source code or runtime was copied or bundled. The small Node OAuth/headless HTTP adapter is original project code using existing dependencies. See DISCORD.md for references and unsupported REST-contract limitations.

## SoundCloud HLS и локальное сопряжение — 1.0.0+9

Веб использует hls.js1.7.3 (Apache-2.0, Dailymotion), подключённый отдельным chunk только для HLS. Native использует cryptography2.9.0 (Apache-2.0) для AES-256-GCM/HKDF локального канала. Неизменённые лицензии сохранены в docs/licenses/Hls-js-Apache-2.0.txt и Cryptography-Apache-2.0.txt; оба уведомления включаются в Windows bundle. Официальные SoundCloud API-потоки используются по условиям платформы, сохраняют attribution и не выдаются за разрешённые offline-загрузки. Виджеты остаются лишь у источников без отдельного разрешённого аудиопути.
