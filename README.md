# proxy-awg2

HTTP-прокси через AmneziaWG2 для сервера docker02.

Проект запускает два контейнера:

- awg2: VPN-клиент AmneziaWG2
- proxy-awg2: HTTP-прокси dumbproxy в той же сетевой namespace

Маршруты хоста не меняются. Вся VPN-маршрутизация изолирована внутри Docker-контейнера.

## Сервер

Сервер: docker02
Адрес прокси: http://192.168.0.8:38109
VPN-интерфейс: awg0
Протокол: AmneziaWG2
Путь проекта: /opt/docker/proxy-awg2

## Файлы

Dockerfile
docker-compose.yml
start.sh
resolv.conf.example
awg-config/awg0.conf.example

Настоящие VPN-конфиги не коммитятся.

Игнорируемые чувствительные файлы:

- awg-config/awg0.conf
- awg-config/awg0.conf.bak
- resolv.conf
- .env
- *.key
- *.pem
- *.log
- state/
- tmp/

## Запуск

cd /opt/docker/proxy-awg2
docker compose up -d --build --wait --wait-timeout 60

## Остановка

cd /opt/docker/proxy-awg2
docker compose down

## Проверка

docker exec awg2 awg show
docker exec awg2 ip addr show awg0
docker exec awg2 ip route show table 51820
curl -x http://192.168.0.8:38109 https://ifconfig.me/ip

## Примечания

Клиент зафиксирован на AWG 2.0 и принудительно использует amneziawg-go. Kernel-модуль AmneziaWG на Docker-хосте не требуется.

Проверка модуля:

modprobe amneziawg
lsmod | grep amneziawg

start.sh добавляет маршрут для локальной сети, чтобы ответы прокси в 192.168.0.0/24 возвращались через eth0, а не через VPN-туннель.

## Безопасность Git

Перед каждым push проверяй отслеживаемые файлы:

git status --short
git ls-files

Эти файлы не должны появляться в git ls-files:

- awg-config/awg0.conf
- awg-config/awg0.conf.bak
- resolv.conf
- .env
- private keys
- logs
