# proxy-awg2

HTTP-прокси с выходом в интернет через туннель AmneziaWG 2.0.

Проект работает на `docker02`. Адрес прокси в локальной сети:

```text
http://192.168.0.8:38109
```

## Архитектура

Compose запускает два контейнера:

- `awg2` поднимает VPN-интерфейс `awg0`.
- `proxy-awg2` запускает `dumbproxy` в сетевом пространстве `awg2`.

```text
LAN-клиент
  -> 192.168.0.8:38109
  -> dumbproxy
  -> awg0
  -> AmneziaWG 2.0
  -> интернет
```

VPN-маршрутизация изолирована внутри контейнера и не изменяет маршруты хоста `docker02`.

`start.sh` добавляет маршрут для `192.168.0.0/24` через `eth0`, чтобы ответы клиентам локальной сети не уходили в VPN.

## Совместимость

Клиент зафиксирован на AWG 2.0:

- `amneziawg-go v0.2.19`
- `amneziawg-tools v1.0.20260618-2`

Туннель принудительно использует `amneziawg-go`. Kernel-модуль AmneziaWG на Docker-хосте не требуется.

Это позволяет работать с self-hosted сервером AWG 2.0, даже если на `docker02` установлен kernel-модуль AWG 3.0.

Версии клиента нельзя обновлять без проверки совместимости с сервером.

## Локальная конфигурация

Рабочие файлы, которые не коммитятся:

```text
awg-config/awg0.conf
resolv.conf
```

Примеры конфигурации:

```text
awg-config/awg0.conf.example
resolv.conf.example
```

## Сборка и запуск

```bash
cd /opt/docker/proxy-awg2
docker compose build awg2
docker compose up -d --wait --wait-timeout 60
```

## Управление

```bash
# Состояние
docker compose ps

# Перезапуск
docker compose restart

# Полное пересоздание
docker compose down
docker compose up -d --wait --wait-timeout 60

# Остановка
docker compose down
```

Контейнер `awg2` имеет healthcheck. `proxy-awg2` запускается после готовности VPN и использует:

```yaml
network_mode: "service:awg2"
```

## Проверка

```bash
docker exec awg2 pgrep -a amneziawg-go
docker exec awg2 ip -brief link show awg0
docker exec awg2 awg show awg0
```

Проверка HTTP-прокси:

```bash
curl -fsS --max-time 30 \
  --proxy http://192.168.0.8:38109 \
  https://api.ipify.org
echo
```

Просмотр журналов:

```bash
docker compose logs --tail 200 awg2
docker compose logs --tail 200 proxy-awg2
```

## Безопасность Git

Перед отправкой изменений:

```bash
git status --short
git ls-files
git diff --cached
```

В Git не должны попадать:

```text
awg-config/awg0.conf
resolv.conf
.env
*.key
*.pem
*.log
state/
tmp/
```
