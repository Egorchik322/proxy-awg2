# proxy-awg2

Изолированный HTTP CONNECT proxy через клиентский AmneziaWG 3.1.

Проект рассчитан на Linux + Docker Compose. VPN-контейнер и proxy-контейнер используют один сетевой namespace; default route хоста не изменяется.

## Архитектура

```text
LAN client
  -> 192.168.0.8:38109/tcp
  -> proxy-awg2 (dumbproxy)
  -> awg2 (AmneziaWG userspace)
  -> AmneziaWG server
  -> internet
```

`awg2` запускает `amneziawg-go v3.1.20260814`, а `awg-quick` и `awg` берутся из `amneziawg-tools v3.1.20260812`. Исходники закреплены тегами и полными commit SHA в `Dockerfile`.

## Требования

- Docker Engine и Docker Compose plugin;
- `/dev/net/tun` на host;
- `CAP_NET_ADMIN`/privileged для VPN-контейнера;
- готовая клиентская конфигурация AmneziaWG 3.1;
- endpoint и ключи, совместимые с серверной стороной.

## Секретная конфигурация

Не коммитьте рабочий конфиг. Создайте root-only каталог и файл:

```bash
sudo install -d -m 0700 /root/awg-client
sudo install -m 0600 -o root -g root awg0.conf /root/awg-client/awg0.conf
```

Публичный шаблон находится в `awg-config/awg0.conf.example`. Он содержит только placeholders. Рабочие `awg-config/*.conf` исключены через `.gitignore`.

Для нестандартного расположения конфига задайте `AWG_CONFIG_DIR`:

```bash
export AWG_CONFIG_DIR=/root/awg-client
docker compose up -d --wait --wait-timeout 60
```

## Сборка и запуск

```bash
docker compose build awg2
docker compose up -d --wait --wait-timeout 60
```

Локальный proxy endpoint: `http://192.168.0.8:38109`.

До запуска убедитесь, что endpoint в конфиге разрешён вашей политикой доступа и серверная сторона использует совместимую версию AmneziaWG.

## Проверка

```bash
docker compose ps
docker exec awg2 pgrep -a amneziawg-go
docker exec awg2 ip -brief link show awg0
docker exec awg2 ip -brief addr show awg0
docker exec awg2 awg show awg0
```

Проверка proxy:

```bash
curl --fail --silent --show-error --max-time 30 \
  --proxy http://192.168.0.8:38109 \
  https://api.ipify.org
echo
```

Проверка маршрутов должна выполняться внутри контейнера и на host отдельно:

```bash
docker exec awg2 ip route show table all
docker exec awg2 ip rule show
ip route
ip rule
```

Host default route не должен меняться. SSH и LAN должны оставаться доступными.

## Обновление конфигурации

1. Сохраните старый конфиг и image digest.
2. Замените `/root/awg-client/awg0.conf` атомарно.
3. Проверьте права `0600 root:root`.
4. Пересоздайте только `awg2` и `proxy-awg2`.
5. Дождитесь healthcheck и проверьте handshake/RX/TX.
6. Проверьте proxy endpoint и DNS.

Не добавляйте `::/0` и IPv6 default route, если серверный профиль их не предусматривает.

## Rollback

```bash
docker compose down
git diff
docker image ls --no-trunc
# восстановить сохранённый awg0.conf и прежний image tag
docker compose up -d --wait --wait-timeout 60
```

Не удаляйте backup до завершения acceptance window.

## Публикация в GitHub

Перед push проверьте:

```bash
git status --short
git ls-files
git diff --cached
```

В репозитории не должны находиться:

```text
/root/awg-client/awg0.conf
awg-config/*.conf
resolv.conf
.env
*.key
*.pem
*.log
```

Публичный репозиторий содержит код запуска, Compose, шаблон конфигурации и инструкции. Приватные ключи, PSK, `HeaderProtectionKey`, endpoint и полные клиентские конфигурации публиковать запрещено.
