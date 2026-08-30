# proxy-awg2

Переносимый Docker Compose-стек с HTTP CONNECT proxy через клиентский AmneziaWG 3.1.

Ветка `awg31` содержит AWG 3.1. AWG 2 сохранён в истории Git и rollback backup, но текущий Compose запускает только AWG 3.1.

## Структура

```text
.
├── Dockerfile
├── docker-compose.yml
├── start.sh
├── awg-config/awg0.conf.example
├── resolv.conf.example
├── .gitignore
└── README.md
```

Рабочие файлы не коммитятся:

```text
/root/awg-client/awg0.conf
awg-config/*.conf
resolv.conf
.env
logs/
backup/
```

## Архитектура

```text
LAN client
  -> PROXY_BIND_IP:PROXY_PORT
  -> proxy-awg2 (dumbproxy)
  -> network namespace awg2
  -> awg0 / amneziawg-go
  -> remote AmneziaWG server
  -> Internet
```

Compose запускает два контейнера:

| Сервис | Назначение |
|---|---|
| `awg2` | AmneziaWG userspace, `awg0`, policy routing и watchdog |
| `proxy-awg2` | HTTP CONNECT proxy в namespace `awg2` |

`proxy-awg2` использует `network_mode: service:awg2`. Внутренний listener всегда `:38108`; внешний bind задаётся `PROXY_BIND_IP` и `PROXY_PORT`.

## Версии

- `amneziawg-go v3.1.20260814`, commit `1b86b2ae0e493e7ea93f8c1a0f0cb6735b1551f1`
- `amneziawg-tools v3.1.20260812`, commit `ee0f0a9aa34ff0a0da4b3433b9512781cfe02843`
- `dumbproxy` закреплён digest в `docker-compose.yml`

`Dockerfile` собирает AWG из точных upstream-тегов с проверкой полных SHA. Kernel-модуль AWG на host не требуется: используется `amneziawg-go`.

## Конфигурация

Рабочий конфиг хранится вне репозитория:

```bash
sudo install -d -m 0700 /root/awg-client
sudo install -m 0600 -o root -g root awg0.conf /root/awg-client/awg0.conf
```

Шаблон без секретов: `awg-config/awg0.conf.example`.

Для другого каталога:

```bash
export AWG_CONFIG_DIR=/root/another-awg-config
```

Resolver задаётся локальным файлом `resolv.conf`, который монтируется в proxy read-only. Он должен быть доступен через AWG; DNS хоста не должен обходить туннель.

## Запуск

```bash
export PROXY_BIND_IP=192.168.0.8
export PROXY_PORT=38109
docker compose build awg2
docker compose up -d --wait --wait-timeout 60
```

По умолчанию proxy: `http://192.168.0.8:38109`.

Не используйте `0.0.0.0` без отдельной firewall-политики.

## Встроенный watchdog

Watchdog находится в `start.sh` внутри контейнера `awg2`. Он не требует host systemd, Docker socket или группы `docker`.

Проверяются:

- процесс `amneziawg-go`;
- интерфейс `awg0`;
- свежесть peer handshake;
- реальные `handshake`, `tx_bytes`, `rx_bytes` из `awg show awg0 dump`;
- внутренний listener `:38108`;
- числовой proxy-canary `http://1.1.1.1/`.

После трёх последовательных combined failure выполняется in-place recovery:

```text
awg-quick down /config/awg0.conf
awg-quick up /config/awg0.conf
```

Network namespace и listener proxy сохраняются, но активные соединения могут кратковременно прерваться. После ограниченного числа неудачных recovery supervisor завершает PID 1, и Docker применяет `restart: unless-stopped`.

Параметры watchdog находятся в `docker-compose.yml`:

```yaml
AWG_WATCHDOG_ENABLED: "true"
AWG_WATCHDOG_INTERVAL: "15"
AWG_HANDSHAKE_MAX_AGE: "180"
AWG_WATCHDOG_FAILURES: "3"
AWG_RECOVERY_COOLDOWN: "300"
AWG_STARTUP_GRACE: "120"
AWG_PROXY_PROBE_TIMEOUT: "8"
AWG_PROXY_CANARY_URL: "http://1.1.1.1/"
AWG_MAX_RECOVERIES: "3"
AWG_RECOVERY_WINDOW: "3600"
```

Один timeout сайта или DNS-запроса сам по себе recovery не запускает.

## Проверка

```bash
docker compose ps
docker inspect awg2 --format '{{.State.Health.Status}}'
docker exec awg2 pgrep -a amneziawg-go
docker exec awg2 awg version
docker exec awg2 ip -brief addr show awg0
docker exec awg2 awg show awg0
docker exec awg2 ip route show table all
docker exec awg2 ip rule
```

Proxy:

```bash
curl --fail --silent --show-error --max-time 30 \
  --proxy http://192.168.0.8:38109 \
  https://example.com/
```

При диагностике сравнивайте два значения handshake/RX/TX с интервалом. Host default route, SSH, LAN и старый legacy listener `38108` не должны изменяться.

## Обновление и rollback

1. Сохраните конфиг, image digest, Compose и `start.sh`.
2. Запишите новый конфиг с правами `0600 root:root` в `/root/awg-client/`.
3. Проверьте parser через pinned image.
4. Выполните `docker compose up -d --force-recreate --wait --wait-timeout 60`.
5. Проверьте handshake, RX/TX, proxy, DNS, IPv6 и маршруты.

Rollback восстанавливает предыдущие config, Compose, `start.sh`, Dockerfile и image digest. Backup удалять только после acceptance window.

Не используйте `docker system prune`, `iptables -F`, `nft flush ruleset`, глобальную смену default route или host-level watchdog.

## Совместимость с AWG 2

Текущий Compose запускает только AWG 3.1. AWG 2 сохранён в commit `6fcde58`, старом image и backup. AWG 3.1-конфиг нельзя передавать старым AWG 2 tools.

## Git

```bash
git status --short
git diff --check
git diff --cached --check
git ls-files
```

Рабочие ключи, PSK, `HeaderProtectionKey`, endpoint и полные конфиги в Git запрещены.
