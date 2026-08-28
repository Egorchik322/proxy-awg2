# proxy-awg2

HTTP CONNECT proxy через клиентский AmneziaWG 3.1 в изолированном Docker network namespace.

Эта ветка `awg31` предназначена для AWG 3.1. Конфигурация AWG 2 не смешивается с конфигурацией AWG 3.1: предыдущая AWG 2 реализация сохранена в истории Git и в rollback backup на сервере.

## Структура проекта

```text
.
├── Dockerfile
├── docker-compose.yml
├── start.sh
├── awg-config/
│   └── awg0.conf.example
├── resolv.conf.example
├── .gitignore
└── README.md
```

Файлы `awg-config/awg0.conf`, `resolv.conf`, `.env`, логи и backup являются локальными файлами и в Git не коммитятся.

## Архитектура

```text
LAN client
  -> 192.168.0.8:38109/tcp
  -> proxy-awg2 (`dumbproxy`)
  -> network namespace `awg2`
  -> `awg0` / AmneziaWG userspace
  -> remote AmneziaWG server
  -> Internet
```

Compose запускает два сервиса:

| Сервис | Назначение |
|---|---|
| `awg2` | AWG 3.1 userspace, интерфейс `awg0`, policy routing внутри контейнера |
| `proxy-awg2` | HTTP CONNECT proxy в namespace `awg2` |

`proxy-awg2` использует `network_mode: service:awg2`, поэтому proxy-трафик проходит через тот же namespace и AWG-маршрут. Глобальный default route Docker-хоста проект не меняет.

## Версии

- `amneziawg-go v3.1.20260814`
  - commit `1b86b2ae0e493e7ea93f8c1a0f0cb6735b1551f1`
- `amneziawg-tools v3.1.20260812`
  - commit `ee0f0a9aa34ff0a0da4b3433b9512781cfe02843`
- `dumbproxy` закреплён digest в `docker-compose.yml`

`Dockerfile` собирает AWG userspace и tools из точных upstream-тегов с проверкой полного commit SHA. Плавающие `latest` для AWG не используются.

## Требования

- Linux host с Docker Engine и Docker Compose plugin;
- доступный `/dev/net/tun`;
- возможность выдать контейнеру `CAP_NET_ADMIN` и `privileged`;
- совместимая клиентская конфигурация AmneziaWG 3.1;
- endpoint и ключи, соответствующие серверной стороне.

## Секретная конфигурация

Рабочий конфиг хранится вне репозитория. По умолчанию Compose использует:

```text
/root/awg-client/awg0.conf
```

Создание root-only каталога и установка файла:

```bash
sudo install -d -m 0700 /root/awg-client
sudo install -m 0600 -o root -g root awg0.conf /root/awg-client/awg0.conf
```

Шаблон без секретов:

```text
awg-config/awg0.conf.example
```

Можно указать другой каталог:

```bash
export AWG_CONFIG_DIR=/root/another-awg-config
docker compose up -d --wait --wait-timeout 60
```

В конфигурации могут использоваться AWG 3.1 поля `I1-I5`, `HeaderProtectionKey`, `ContentPaddingAddition`, `Rekey*`, `KeepaliveTimeout`, `MaxHandshakeAttempts`, `RandomTrailers` и `DisableCookies`. Их значения нельзя придумывать или переносить из другого профиля.

## Локальный resolver

Compose монтирует локальный файл `resolv.conf` в proxy-контейнер:

```text
./resolv.conf:/etc/resolv.conf:ro
```

Файл `resolv.conf` не коммитится. Для рабочего профиля он должен содержать resolver, доступный из AWG namespace. Если DNS недоступен, числовые IP могут работать, а доменные CONNECT-запросы будут завершаться ошибкой разрешения имени.

## Сборка и запуск

Из корня репозитория:

```bash
docker compose build awg2
docker compose up -d --wait --wait-timeout 60
```

Локальный endpoint по умолчанию:

```text
http://192.168.0.8:38109
```

Публикация выполняется только на указанном LAN-адресе. Не открывайте proxy endpoint в WAN без отдельной firewall-политики.

## Проверка

Статус контейнеров:

```bash
docker compose ps
docker inspect awg2 --format '{{.State.Health.Status}}'
```

AWG userspace и интерфейс:

```bash
docker exec awg2 pgrep -a amneziawg-go
docker exec awg2 awg version
docker exec awg2 ip -brief addr show awg0
docker exec awg2 ip link show awg0
docker exec awg2 awg show awg0
```

Маршруты должны проверяться внутри AWG-контейнера и на host отдельно:

```bash
docker exec awg2 ip route show table all
docker exec awg2 ip rule show
ip route
ip rule
```

Проверка proxy по числовому адресу:

```bash
curl --fail --silent --show-error --max-time 30 \
  --proxy http://192.168.0.8:38109 \
  http://1.1.1.1/
```

Проверка доменного HTTPS возможна только после проверки resolver из конфига:

```bash
curl --fail --silent --show-error --max-time 30 \
  --proxy http://192.168.0.8:38109 \
  https://example.com/
```

При проверке фиксируйте два значения handshake, RX и TX с интервалом и проверяйте, что счётчики растут после proxy-запроса.

## Обновление AWG-конфига

1. Сохраните текущий конфиг и image digest.
2. Подготовьте новый файл вне Git.
3. Проверьте права `0600 root:root`.
4. Проверьте parser через pinned image до production restart.
5. Пересоздайте только `awg2` и `proxy-awg2`.
6. Дождитесь healthcheck.
7. Проверьте handshake, RX/TX, маршруты, DNS и proxy.

```bash
docker compose up -d --force-recreate --wait --wait-timeout 60
```

Не добавляйте `::/0` или IPv6 default route, если это не предусмотрено серверным профилем.

## Остановка и rollback

Остановка только этого проекта:

```bash
docker compose down
```

Rollback должен восстанавливать ранее сохранённые Compose, Dockerfile, startup и AWG-конфиг. До завершения acceptance window не удаляйте старый image и backup.

В production-среде не используйте `docker system prune`, глобальный `iptables -F`, `nft flush ruleset` или замену default route хоста.

## Совместимость с AWG 2

Текущая ветка `awg31` запускает только AWG 3.1 и не предназначена для AWG 2 конфигов.

AWG 2 сохранён:

- в Git commit `6fcde58`;
- в старом image и backup на docker02;
- в отдельном legacy-стеке, если он ещё развёрнут.

AWG 2 нельзя запускать с AWG 3.1 конфигом: старые tools не знают новые поля. Для возврата к AWG 2 нужно восстановить согласованный AWG 2 конфиг и старую версию образа целиком.

## Git workflow

Проверка перед commit:

```bash
git status --short
git diff --check
git diff --cached --check
git ls-files
```

Публикуемый набор должен содержать только код, Compose, startup, example-конфиг и документацию. Рабочие ключи и секреты в Git запрещены.

Публикация ветки:

```bash
git push -u origin awg31
```

После публикации ветку `awg31` можно выбрать default branch в GitHub: `Settings` -> `Branches` -> `Default branch` -> `Switch` -> `awg31`. Это настройка GitHub-репозитория, она не меняется обычным commit.
