#!/bin/bash

set -euo pipefail

APP_PORT=8080
REPO_URL="https://github.com/Lissy93/dashy.git"
IMAGE_NAME="dashy-custom:latest"
TARBALL="dashy-image.tar"
WORKDIR="./dashy-deploy"
CONFIG_FILE="./dashy-config.yml"
CONTAINER_NAME="dashy-app"

echo "=== Запуск скрипта: развертывание Dashy ==="

# 1. Проверка доступности Docker
echo "1. Проверяю, что Docker запущен и доступен..."
if ! docker info > /dev/null 2>&1; then
    echo "Ошибка: Docker не работает или недоступен. Убедитесь, что служба docker запущена и окружение настроено корректно."
    exit 1
fi
echo "Docker работает."

# 2. Проверка интернета и репозитория
echo "2. Проверяю подключение к интернету и репозиторию..."
if ! ping -c1 -W5 github.com > /dev/null 2>&1; then
    echo "Ошибка: Нет подключения к интернету."
    exit 1
fi

if ! git ls-remote --quiet "$REPO_URL" > /dev/null 2>&1; then
    echo "Ошибка: Не удалось получить доступ к репозиторию $REPO_URL"
    exit 1
fi
echo "Интернет и репозиторий доступны."

# 3. Создание Dockerfile на основе alpine:3.17
echo "3. Создаю Dockerfile..."

rm -rf "$WORKDIR"
mkdir -p "$WORKDIR"
cd "$WORKDIR"

cat > Dockerfile << 'EOF'
FROM alpine:3.17

RUN apk add --no-cache \
    nodejs \
    npm \
    git

# Клонируем репозиторий
RUN git clone https://github.com/Lissy93/dashy.git /app
WORKDIR /app

# Устанавливаем ВСЕ зависимости для сборки
RUN npm install

# Собираем приложение
RUN npm run build

# Удаляем node_modules и устанавливаем только production-зависимости
RUN rm -rf node_modules && npm install --omit=dev

# Устанавливаем http-server для раздачи статики
RUN npm install -g http-server

EXPOSE 80

# Запускаем сервер
CMD ["http-server", "dist", "-p", "80", "-a", "0.0.0.0", "--cors", "--gzip"]
EOF

echo "Dockerfile создан."

# 4. Сборка образа
echo "4. Собираю Docker-образ..."
docker build -t "$IMAGE_NAME" .

# 5. Сохранение образа в файл
echo "5. Сохраняю образ в файл $TARBALL..."
docker save "$IMAGE_NAME" -o "$TARBALL"

if [ ! -f "$TARBALL" ]; then
    echo "Ошибка: Файл образа $TARBALL не был создан."
    exit 1
fi
echo "Образ сохранён в файл $TARBALL."

# 6. Очистка Docker
echo "6. Очищаю Docker: останавливаю и удаляю контейнеры и образы..."

docker ps -aq | xargs -r docker stop > /dev/null 2>&1 || true
docker ps -aq | xargs -r docker rm > /dev/null 2>&1 || true
docker images -q | xargs -r docker rmi > /dev/null 2>&1 || true

echo "Docker очищен."

# 7. Загрузка образа из файла
echo "7. Загружаю образ из файла..."
docker load -i "$TARBALL"

if ! docker images | grep dashy-custom > /dev/null; then
    echo "Ошибка: Образ не был загружен."
    exit 1
fi
echo "Образ загружен."

# 8. Создание docker-compose.yml
echo "8. Создаю docker-compose.yml..."

if docker compose version > /dev/null 2>&1; then
    DOCKER_COMPOSE_CMD="docker compose"
elif command -v docker-compose > /dev/null; then
    DOCKER_COMPOSE_CMD="docker-compose"
else
    echo "Ошибка: Не найдена команда 'docker compose' или 'docker-compose'."
    exit 1
fi

cat > docker-compose.yml << EOF
version: '3.8'
services:
  dashy:
    image: $IMAGE_NAME
    container_name: $CONTAINER_NAME
    ports:
      - "127.0.0.1:$APP_PORT:80"
    restart: unless-stopped
    volumes:
      - ../dashy-config.yml:/app/public/conf.yml:ro
EOF

echo "Файл docker-compose.yml создан."

# 9. Создание конфигурации дашборда (задание 3)
echo "9. Создаю локальный файл конфигурации дашборда..."

cd ..

cat > "$CONFIG_FILE" << 'EOF'
appConfig:
  theme: dark
  layout: horizontal
  hideHeader: false
  showTitle: true
  pageTitle: My Custom Dashboard
  sections:
    - name: Services
      icon: fas fa-cogs
      items:
        - title: GitLab
          description: Internal Git server
          icon: fab fa-gitlab
          url: https://gitlab.local
          target: newtab
        - title: Grafana
          description: Monitoring dashboard
          icon: fas fa-chart-line
          url: https://grafana.local
          target: newtab
EOF

echo "Файл конфигурации дашборда создан: $CONFIG_FILE"

# 10. Запуск контейнера через docker-compose
echo "10. Запускаю контейнер..."
cd "$WORKDIR"
$DOCKER_COMPOSE_CMD up -d

# 11. Проверка работоспособности
echo "11. Проверяю работоспособность приложения..."

sleep 15

if ! docker ps | grep "$CONTAINER_NAME" | grep -q "Up"; then
    echo "Ошибка: Контейнер $CONTAINER_NAME не запущен."
    docker logs "$CONTAINER_NAME"
    exit 1
fi

if ! curl -f -s -H "Host: localhost" "http://127.0.0.1:$APP_PORT" -m 10 > /dev/null; then
    echo "Ошибка: Приложение не отвечает на http://127.0.0.1:$APP_PORT"
    docker logs "$CONTAINER_NAME"
    exit 1
fi

echo "Приложение успешно запущено."
echo "Дашборд доступен по адресу: http://127.0.0.1:$APP_PORT"
echo "Конфигурация загружена из локального файла $CONFIG_FILE"

echo "=== Скрипт завершён успешно ==="
