# Botswain

Self-hosted инструмент для управления Telegram-ботами на VPS и на локальном ПК.

Desktop-приложение (Flutter, Linux) подключается к серверу по SSH, само ставит
Docker и поднимает агента, а дальше управляет ботами через единый control-API.
Каждый бот запускается как отдельный контейнер с автоперезапуском и лимитами
ресурсов.

Open-source пет-проект.

## Как это устроено

```
┌────────────────────┐        SSH (только bootstrap + туннель)
│  App (Flutter,     │───────────────────────────────────────────┐
│  Linux desktop)    │                                           │
│  ┌──────────────┐  │       control-API (HTTP/WS через туннель) │
│  │ botswain_core│  │◄───────────────────────────────┐          ▼
│  └──────────────┘  │                                │   ┌─────────────────┐
└────────────────────┘                                └───│  Agent (Go,     │
                                                          │  в контейнере)  │
                                                          │  docker.sock ─► │
                                                          │  боты-контейнеры│
                                                          └─────────────────┘
```

- **Клиент** общается с агентом **только** через control-API. Произвольный шелл
  по SSH из GUI не используется — SSH нужен лишь для первичного bootstrap и для
  поднятия port-forward туннеля.
- **Агент** — один статический Go-бинарник, живёт в контейнере, монтирует
  `/var/run/docker.sock` и рулит ботами как соседними контейнерами
  (docker-out-of-docker). Биндится на loopback, публично в сеть не торчит.
- **Туннель** (SSH port-forward) — это и есть аутентификация и шифрование.
- **Локальный режим** — тот же агент на `127.0.0.1` напрямую, тот же API, без
  туннеля. Docker требуется и локально.

Подробнее — [docs/architecture.md](docs/architecture.md) и контракт API
[docs/control-api.md](docs/control-api.md).

## Структура репозитория

```
Botswain/
├── docs/            # архитектура и контракт control-API (общие для agent и app)
├── agent/           # Go: control-API, живёт в контейнере
└── app/             # Flutter desktop (Linux)
    └── packages/
        └── botswain_core/   # вся не-UI логика (SSH, туннель, API, секреты)
```

## Стек

- **Agent:** Go, официальный Docker SDK (позже), роутер `chi`, `net/http`.
- **App:** Flutter desktop (Linux), `dartssh2` (SSH exec + SFTP + port-forward),
  `flutter_secure_storage` (Linux → libsecret), `fl_chart` (метрики, позже).

## Статус

### Milestone 1 — готов

Сквозной путь «подключились → агент работает → отвечает».

- [x] Скелет монорепо + контракт control-API v0
- [x] Agent: health-эндпоинт, биндинг на loopback, Dockerfile
- [x] App: экран «добавить сервер» → SSH → проверка Docker → `docker run` агента
      → туннель → health → индикация «агент жив»
- [x] Креды через `flutter_secure_storage`
- [x] Устойчивость к разрыву туннеля (reconnect с backoff)

### Milestone 2 — готов

Жизненный цикл ботов как соседних Docker-контейнеров.

- [x] Контракт `/v0/bots` (create/list/get/start/stop/restart/delete)
- [x] Agent: bot-manager на официальном Docker SDK, код бота в per-bot volume,
      зависимости из `requirements.txt`, лимиты и автоперезапуск; health
      отражает доступность Docker
- [x] Состояние ботов — в labels контейнеров (без отдельной БД)
- [x] App: список ботов и форма создания (выбор `.py` + `requirements.txt`)

### Milestone 3 — готов

Наблюдаемость ботов: метрики и логи.

- [x] Контракт: `GET /v0/bots/{id}/metrics` (снапшот CPU/RAM) и
      `GET /v0/bots/{id}/logs` (WebSocket)
- [x] Agent: метрики через Docker stats (CPU% по двум замерам), стриминг логов
      по WebSocket (`coder/websocket` + демультиплексирование `stdcopy`)
- [x] App: экран бота — живые метрики (`fl_chart`) и консоль логов в реальном
      времени

Дальнейшие milestone'ы (egress-прокси к `api.telegram.org`, Android) — см.
[docs/architecture.md](docs/architecture.md).

## Сборка

### Agent

```bash
cd agent
go build -o bin/agent ./cmd/agent
./bin/agent --port 8080
curl -s http://127.0.0.1:8080/v0/health
```

Или в контейнере:

```bash
cd agent
docker build -t botswain-agent .
docker run --rm -p 127.0.0.1:8080:8080 botswain-agent
```

### App

Системные предзависимости (Linux desktop): для сборки нужны GTK и `libsecret`
(бэкенд `flutter_secure_storage`). На Fedora:

```bash
sudo dnf install libsecret-devel gtk3-devel
```

(на Debian/Ubuntu — `libsecret-1-dev libgtk-3-dev`.)

```bash
cd app
flutter pub get
flutter run -d linux
```
