#!/bin/bash
# ===========================================
# Починка повреждённого Redis AOF
# Запускать на сервере из /opt/email-sender
# ===========================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

cd /opt/email-sender

echo -e "${YELLOW}Останавливаю Redis...${NC}"
docker compose stop redis

echo -e "${YELLOW}Попытка починить AOF (redis-check-aof --fix)...${NC}"
# Redis 7: AOF в appendonlydir, манифест appendonly.aof.manifest или appendonly.aof.N.manifest
FIXED=0
for manifest in appendonly.aof.manifest appendonly.aof.6.manifest; do
  path="/data/appendonlydir/$manifest"
  if docker compose run --rm redis sh -c "test -f $path" 2>/dev/null; then
    echo "  Найден манифест: $path"
    # Автоматически подтверждаем fix (echo y)
    docker compose run --rm redis sh -c "echo y | redis-check-aof --fix $path" && FIXED=1
    break
  fi
done

if [ "$FIXED" = "0" ]; then
  # Старый формат или один файл
  if docker compose run --rm redis sh -c "test -f /data/appendonly.aof" 2>/dev/null; then
    docker compose run --rm redis sh -c "echo y | redis-check-aof --fix /data/appendonly.aof" && FIXED=1
  fi
fi

if [ "$FIXED" = "0" ]; then
  echo -e "${RED}AOF починить не удалось.${NC}"
  echo ""
  echo "Удалить том и поднять Redis с пустой БД (очереди Sidekiq очистятся)? [y/N]"
  read -r confirm
  if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
    docker volume rm email_redis_data 2>/dev/null || true
    echo -e "${GREEN}Запускаю Redis с пустым томом...${NC}"
    docker compose up -d redis
    echo -e "${GREEN}Готово.${NC}"
    exit 0
  fi
  echo "Redis не запущен. Для ручного сброса: docker volume rm email_redis_data && docker compose up -d redis"
  exit 1
fi

echo -e "${GREEN}Запускаю Redis...${NC}"
docker compose up -d redis

echo ""
echo -e "${YELLOW}Рекомендация для хоста (устраняет WARNING Memory overcommit):${NC}"
echo "  sudo sysctl vm.overcommit_memory=1"
echo "  echo 'vm.overcommit_memory = 1' | sudo tee -a /etc/sysctl.conf"
echo ""
echo -e "${GREEN}Готово. Проверка: docker compose logs redis --tail=20${NC}"
