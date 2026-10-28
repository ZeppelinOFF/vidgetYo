# VidgetYo

Виджет задач на рабочем столе macOS. Он показывает список из веб-приложения, отмечает пункты выполненными и умеет добавлять новые.

Иконка в меню-баре — чеклист. Окно лежит на обоях и на всех рабочих столах. Обычные окна его закрывают; пункт «Поверх окон» поднимает его над ними. Перетаскивание — за пустое место карточки.

## Запуск

Откройте `VidgetYo.xcodeproj` и нажмите Run.

Либо из терминала:

```bash
xcodebuild -project VidgetYo.xcodeproj -scheme VidgetYo -configuration Debug -derivedDataPath build build
open build/Build/Products/Debug/VidgetYo.app
```

В настройках укажите адрес API. Для проверки без своего сервера:

```bash
python3 examples/server.py
```

Адрес: `http://127.0.0.1:8787/tasks`

## API

`GET {адрес}`

```json
{ "tasks": [ { "id": "1", "title": "Купить молоко", "done": false, "due": "2026-10-28", "url": "https://example.com/tasks/1" } ] }
```

Подойдёт и голый массив, и обёртки `data` / `items`. Вместо `title` можно прислать `name`, вместо `done` — `completed` или `isDone`.

`POST {адрес}` с телом `{"title":"Новая задача"}`.

`PATCH {адрес}/{id}` с телом `{"done":true}`.

Если в настройках указан токен, каждый запрос получает `Authorization: Bearer …`.

## Пакет

На Mac с Xcode 27:

```bash
./scripts/build-installer.sh
```

Готовый образ: `dist/VidgetYo-<версия>-macOS27-arm64.dmg`. Сборка Release, только Apple Silicon. Без Developer ID подпись ad-hoc: при первом запуске может понадобиться Control-click по приложению и «Открыть».

## Версии

В `MARKETING_VERSION` лежит последняя выпущенная версия, формат `major.minor.patch`.

Пуш в `main` запускает Action: по сообщениям коммитов версия поднимается, собирается DMG и публикуется GitHub Release `vX.Y.Z`.

- `major` в сообщении коммита поднимает первую цифру
- `minor` поднимает вторую
- любое другое сообщение поднимает третью

Коммит с поднятой версией бот пушит сам и помечает `[skip ci]`, чтобы сборка не зациклилась. Сейчас в проекте `0.1.0`, первый пуш в `main` выпустит `0.1.1`.
