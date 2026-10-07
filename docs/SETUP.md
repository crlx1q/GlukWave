# Запуск и подключения GlukWave

## Локально

Запустите `outputs/Start-GlukWave.ps1` или `npm install`, `npm run keys`, `npm run dev` из корня. При занятом порте5173 Vite не должен незаметно переходить на другой порт: поменяйте порт и `APP_URL` вместе, чтобы OAuth callback и ссылки QR оставались правильными.

Для телефона в одной сети задайте `HOST=0.0.0.0`, `LAN_DISCOVERY=true`, запустите сервер заново. В приложении укажите `http://IP-компьютера:4000`. Разрешите входящие TCP4000 и UDP4001 в Windows Firewall для вашей частной сети. Само приложение не изменяет firewall. Для QR с телефона веб также должен быть доступен: запустите Vite с `--host 0.0.0.0`, установите `APP_URL=http://IP-компьютера:5173` и добавьте этот origin. До HTTP LAN настройки предпочтительнее production HTTPS с вашим доменом; cleartext в Android разрешён только debug build.

Без интернета сервер в этой же локальной сети продолжает управлять устройствами и комнатами; уже кешированная музыка играет локально. Децентрализованного управления без общего доступного сервера нет. При работе в разных сетях нужен сервер, доступный обеим сторонам через интернет.

## MongoDB Atlas

`DB_DRIVER=mongo`, `MONGODB_URI=<connection string>`, `MONGODB_DATABASE=glukwave`. URI храните только в `.env`. Создайте пользователя с правами на эту базу и настройте разрешённые IP сервера в Atlas. Не используйте общий админ-аккаунт кластера. Сохраните тот же `TOKEN_ENCRYPTION_KEY`. Переключение драйвера выбирает другую базу, автоматически переносить SQLite записи не будет. Для переноса используйте `npm run migrate -- --from sqlite --to mongo` после настройки `.env` и резервной копии. Сначала будет только подсчёт и проверка конфликтов; для записи добавьте `--apply` и остановите сервер. Исходная база сохраняется; разные существующие записи назначения не перезаписываются.

## Локальная музыка / R2

По умолчанию `MEDIA_STORAGE=local`. Для Cloudflare R2: `MEDIA_STORAGE=r2`, `R2_ENDPOINT=https://ACCOUNT_ID.r2.cloudflarestorage.com`, bucket, access key и secret. Бакет оставьте приватным: доступ выдаёт сервер с проверкой сессии/комнаты. Сервер потоково обслуживает Range из R2. Смена media driver не переносит уже загруженные оригиналы: для существующей библиотеки сначала переносите содержимое `var/media` с сохранением ключей `audio/...` и `images/...`. Не удаляйте локальные файлы до проверки.

## Регистрация и почта

`TURNSTILE_SITE_KEY` публичный, `TURNSTILE_SECRET_KEY` только серверный. Сервер вызывает Siteverify, production проверяет hostname. Данные клиентского widget без серверной проверки не принимаются. Локально при пустых ключах CAPTCHA отключена явно для разработки; это не защита ботов. Тестовые ключи Cloudflare не используйте в production.

`SMTP_URL=smtps://username:password@smtp.example.com:465` (пароль/имя URL-encode при специальных символах). `MAIL_FROM` ваш подтверждённый отправитель. `REQUIRE_EMAIL_VERIFICATION=true` для реальных пользователей. Локальная папка mailbox доступна администратору в режиме development, production маршрут отключён. Сброс пароля одноразовый, действует30мин и завершает все существующие сессии. Без SMTP обычный запрос восстановления возвращает503 с понятным сообщением о недоступности, вместо утверждения об отправке письма. Тестовый режим использует отдельный mailbox для проверки одноразовых ссылок.

Все настройки в этом документе выполняет владелец сервера. Пользователи вводят свою почту/пароль или проходят официальный OAuth, но не получают и не добавляют API-ключи. Технические причины недоступности интеграций доступны только административной консоли.

## Форма звука для визуализации

`ffmpeg-static` устанавливает FFmpeg при установке npm-зависимостей; если lifecycle-скрипты запрещены вашим npm, разрешите установку именно этого пакета и выполните `npm rebuild ffmpeg-static`. Dockerfile делает это явно после `npm ci --ignore-scripts`. Сервер декодирует только разрешённый защищённый локальный/R2 поток в измеренную RMS-огибающую. Он не принимает произвольный URL для FFmpeg и не сохраняет полную PCM-копию. Публичные треки SoundCloud используют огибающую `wave.sndcdn.com`; звук площадки остаётся в официальном плеере.

Измеренные массивы хранятся в воспроизводимом кеше коллекции `waveforms`. Они могут быть вычислены заново после переноса базы; аудио, авторизация и плейлисты от этого кеша не зависят. На один процесс разрешены2 декодирования и20 ожидающих задач, лимит30с и128MiB вывода. При отсутствии данных интерфейс оставляет спокойную волну и не изображает выдуманную реакцию на музыку. Лицензии зависимостей описаны в `docs/THIRD-PARTY.md`.

## OAuth callback адреса

Зарегистрируйте следующие адреса точно, заменяя origin на `APP_URL`:

| Сервис | Redirect URI | ENV |
|---|---|---|
| Вход Google | `/api/auth/google/callback` | GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET |
| YouTube библиотека | `/api/integrations/youtube/callback` | те же Google ключи, Youtube readonly scope |
| Spotify | `/api/integrations/spotify/callback` | SPOTIFY_CLIENT_ID, SPOTIFY_CLIENT_SECRET |
| SoundCloud | `/api/integrations/soundcloud/callback` | SOUNDCLOUD_CLIENT_ID, SOUNDCLOUD_CLIENT_SECRET |
| Discord аккаунт | `/api/integrations/discord/callback` | DISCORD_CLIENT_ID, DISCORD_CLIENT_SECRET |

Google Cloud: включите YouTube Data API v3, создайте отдельный `YOUTUBE_API_KEY` для поиска, OAuth consent screen и тестовых пользователей. Сервер проверяет подпись Google ID token, issuer, audience и nonce. OAuth токены подключённых сервисов зашифрованы AES-256-GCM, refresh на сервере.

Spotify используйте loopback `127.0.0.1`, не `localhost`, для локального callback. В development mode действуют ограничения Spotify и Premium; полный SDK не заменяет подписку. Импорт поддерживает текущий `/playlists/{id}/items` и данные `item`/`track`.

SoundCloud уже работает без ключей для публичных треков: сервер читает результаты публичной страницы поиска и метаданные страницы трека; воспроизведение идёт через официальный Widget API. Например, поиск `Forss` возвращает настоящие записи с обложками и длительностью. `SOUNDCLOUD_PUBLIC_SEARCH=true` включён по умолчанию; `false` оставляет публичные ссылки и поиск через ваш настроенный API. Кеш результатов —5мин, метаданных —1час; не более4 одновременных запросов и180 запросов к сайту за минуту на процесс. Публичная HTML-разметка может меняться; ошибки площадки показываются пользователю. Для входа и импорта своей закрытой библиотеки нужны зарегистрированное приложение, OAuth2.1/PKCE и access token. Чужие client_id не извлекаются и не используются. Яндекс Музыка: CSV/JSON экспорт с title/artist/sourceUrl; неподключённый закрытый API не скрывается за фиктивной кнопкой входа.

## Формат импорта

CSV: `title,artist,album,url` или Spotify-export `Track Name,Artist Name(s),Album Name,Track URI`. JSON:

```json
{"tracks":[{"title":"Название из экспорта","artist":"Исполнитель","sourceUrl":"https://music.yandex.ru/album/ALBUM_ID/track/TRACK_ID"}]}
```

Это формат пользовательских данных, а не поставляемый трек. Строки без валидной ссылки площадки пропускаются с ошибкой. Данные из экспорта остаются приватными для импортировавшего пользователя; уже проверенная запись площадки используется повторно и не перезаписывается названиями из CSV. Аудио не появляется из CSV: проигрывается официальный плеер источника. Для offline загрузите оригинальный аудиофайл.

## Discord и push

Discord Application ID в `DISCORD_CLIENT_ID`; загрузите asset `glukwave` в Developer Portal, при необходимости разрешите Rich Presence. В Windows должен быть запущен Discord. Включите desktop bridge в настройках и введите его код в вебе: bridge слушает только127.0.0.1:4002, проверяет origin и код. Веб/телефон OAuth связывает аккаунт, но сам по себе не публикует presence.

Web Push: `npm run keys` генерирует VAPID. Разрешение уведомлений запрашивается пользователем в настройках; production HTTPS обязателен. Android/iOS: сервисный аккаунт Firebase `FCM_PROJECT_ID`, `FCM_CLIENT_EMAIL`, `FCM_PRIVATE_KEY`; в Flutter передайте Firebase options через dart-define, как указано в `apps/native/README.md`. Без реальных Firebase options FCM отключён.

## Публичный запуск

Unbound: optional Stripe Checkout. Создайте recurring Price в Stripe, задайте `STRIPE_SECRET_KEY`, `STRIPE_UNBOUND_PRICE_ID` и `STRIPE_WEBHOOK_SECRET`; webhook URL `APP_URL/api/billing/webhook`, события `checkout.session.completed`, `customer.subscription.created/updated/deleted`. Сервер проверяет подпись по исходным байтам, связывает session с пользователем и получает текущую подписку Stripe. Успешный redirect не активирует тариф. Customer Portal нужно включить в Stripe для отмены/управления. Сначала проверяйте на собственном Stripe test mode, затем меняйте ключи; реальных платежей во время разработки не выполнялось. [Официальная документация Checkout](https://docs.stripe.com/api/checkout/sessions/create).

Доменные файлы подготовки: `deploy/Caddyfile`, `Dockerfile`, `compose.yaml`. Они не были развёрнуты. Production requires реальные SMTP/Turnstile и HTTPS APP_URL; не выставляйте локальный development сервер в интернет.

После запуска для нескольких друзей дополнительно настройте резервное копирование Mongo/SQLite и оригиналов, ограничения хранилища/логов и мониторинг. Текущий универсальный repository API ограничивает чтение коллекции10000документами; до масштабирования замените фильтрацию коллекций запросами/пагинацией и вынесите лимиты в Redis для нескольких процессов. Сервер предназначен для одного процесса, durable state сохраняется, realtime устройство подключено к этому процессу.

## Языки и сайт

Основной язык — английский; доступны ru/kk/uk/de/es и автоматический режим. Выбранный язык хранится в общих настройках аккаунта и локально у гостя. Автоматический выбор использует серверную базу стран IP, затем язык браузера/телефона и английский. IP посетителя не передаётся внешнему геосервису. База IPv4/IPv6 находится в `apps/server/data/geoip`; источник, контрольные суммы и лицензия указаны рядом. `npm run geoip:update` обновляет её по проверенным данным, после чего нужен перезапуск сервера. `GEOIP_DATA_DIR` меняет каталог владельца.

`TRUST_PROXY` должен соответствовать реально защищённому обратному прокси. При прямом локальном запуске оставьте0: произвольные X-Forwarded-For/CF-IPCountry не должны определять страну посетителя. IP-география приблизительна; ручной выбор языка имеет приоритет.

Сайт-визитка работает на `/`, музыкальное приложение — на `/app/`. Старые ссылки с музыкальными hash-маршрутами, QR/OAuth и приглашения сохраняются. Оба интерфейса доступны на шести языках; сохранённый язык общий для сайта и приложения. Service worker сохраняет обе оболочки и мини-плеер, исключая ответы API и авторизации. `APP_URL` остаётся origin без `/app`, поскольку сервер строит на нём также `/api` callback-ссылки. Фактические проверки записаны в `outputs/VERIFICATION.md`.

Публичные скачивания обслуживаются из `RELEASES_DIR` (по умолчанию `outputs`) по `releases.json`. Регистрируйте только проверенный фактический пакет; маршрут сам проверяет SHA-256 и размер, скрывает отсутствующие/изменённые файлы и не открывает локальную базу или исходники по произвольному пути. Пример после успешной сборки: `node scripts/register-release.mjs android GlukWave-android-debug.apk 1.0.0 debug`. Для production разместите подписанные release-пакеты в примонтированном каталоге; debug APK предназначен для локального тестирования.

## Официальные источники

- [SoundCloud API Guide](https://developers.soundcloud.com/docs/api/guide) — OAuth2.1, регистрация app, поиск и streams.
- [SoundCloud oEmbed](https://developers.soundcloud.com/docs/oembed) и [Widget API](https://developers.soundcloud.com/docs/api/html5-widget) — публичные ссылки и управление официальным плеером без ключей приложения.
- [Spotify Web Playback SDK](https://developer.spotify.com/documentation/web-playback-sdk/reference) — требования Premium и события проигрывателя.
- [Spotify Playlist Items](https://developer.spotify.com/documentation/web-api/reference/get-playlists-items) — текущий endpoint импорта.
- [YouTube Developer Policies Guide](https://developers.google.com/youtube/terms/developer-policies-guide) — ограничения offline и background.
- [Google OpenID](https://developers.google.com/identity/openid-connect/reference) — проверка ID token.
- [Яндекс: официальный embed](https://www.yandex.ru/support/wiki/ru/actions/iframe) — формат iframe трека.
- [Cloudflare Siteverify](https://developers.cloudflare.com/turnstile/get-started/server-side-validation/) — серверная проверка CAPTCHA.
