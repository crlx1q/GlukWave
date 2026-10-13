# GlukWave рядом с VPN и Telegram-ботом

Подготовлен отдельный Compose-проект в `/www/wwwroot/glukwave`. Его единственный сервис `wave` ограничен **1 CPU, 4 ГиБ RAM, 256 процессами**; лимит охватывает Node и дочерние Python/FFmpeg. Внутри Node heap ограничен 2 ГиБ: это часть общего лимита, а не дополнительная память. База SQLite и локальные медиа живут в `./var`, проверенные APK/EXE — в `./outputs`. Текущие процессы VPN, сайт и бот не включаются в этот Compose-проект.

Этот профиль пока не применён на сервере. В `.env` следует явно выбрать `DB_DRIVER=sqlite`: одного удаления `MONGODB_URI` недостаточно, если оставлен `DB_DRIVER=mongo`. Существующие данные MongoDB сами в SQLite не переносятся; миграция отложена владельцем.

После размещения проекта и настройки `.env`, для управления используется точное имя проекта и его папка:

```sh
docker compose --project-name glukwave --project-directory /www/wwwroot/glukwave up -d --build wave
docker compose --project-name glukwave --project-directory /www/wwwroot/glukwave restart wave
docker compose --project-name glukwave --project-directory /www/wwwroot/glukwave logs --tail 100 wave
docker stats --no-stream glukwave-wave-1
```

Вторая команда перезапускает только `wave` в проекте `glukwave`. Это предусмотрено [Docker Compose restart](https://docs.docker.com/reference/cli/docker/compose/restart/). Название контейнера в `docker stats` нужно сверить с фактическим `docker compose --project-name glukwave --project-directory /www/wwwroot/glukwave ps`: Compose может использовать другой формат имени.

aaPanel может управлять отдельным Compose-проектом через свой Docker-модуль; доступные действия зависят от установленной версии. [Официальное руководство модуля](https://www.aapanel.com/forum/d/13701-docker-moduleuser-manual/7). Для `wave.gluk.tech` используйте существующий reverse proxy на `127.0.0.1:4000` с WebSocket. Не запускайте дополнительный Caddy на занятых 80/443 и не меняйте конфигурацию VPN/бота.

В Compose уже включён `SERVICE_RESTART_ENABLED=true`, а политика `restart: unless-stopped` запускает GlukWave после штатного закрытия его процесса. [Политики перезапуска Docker](https://docs.docker.com/engine/containers/start-containers-automatically/). При самостоятельном запуске Node этот флаг должен оставаться `false`.

В админке показываются две разные величины: CPU/RAM самого Node и CPU/RAM всего контейнера, включая извлечение/конвертацию аудио. На Linux с доступным cgroup показываются фактический бюджет и его процент использования. Без этих счётчиков значения остаются неизвестными, а не выдаются за нулевую нагрузку. История хранит последние 120 замеров с интервалом 5 секунд в памяти процесса; это 10 минут, без постоянных записей в базу.

Кнопка перезапуска доступна только владельцу из `ADMIN_EMAILS` с ролью admin. Сервер проверяет права, точное подтверждение, включённый менеджер и повтор запроса; действие сохраняется в аудит. Сначала возвращает ответ, затем закрывает **только свой процесс**. Код не получает Docker socket, shell или право перезагрузки хоста. Для наблюдения после релиза нужно смотреть реальные графики и логи: локальные проверки не доказывают отсутствие утечки на production.
