#!/bin/bash
# Simple Docker Compose watchdog — recreates containers if a URL returns 404

# ==== CONFIGURATION ====
URL="http://localhost:8081/settings"    # URL to check
COMPOSE_DIR="/opt/redlib"              # Folder containing docker-compose.yml
LOG_FILE="/var/log/docker-watchdog.log"
CHECK_INTERVAL=600                    # 5 minutes = 300 seconds

# ==== FUNCTION ====
check_url() {
  local status
  status=$(curl -s -o /dev/null -w "%{http_code}" "$URL" || echo "000")
  echo "$(date '+%Y-%m-%d %H:%M:%S') - Checked $URL → HTTP $status" >> "$LOG_FILE"

  if [ "$status" = "404" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - URL returned 404, forcing Docker Compose recreate..." >> "$LOG_FILE"
    (cd "$COMPOSE_DIR" && docker compose up -d --force-recreate) >> "$LOG_FILE" 2>&1
  fi
}

# ==== MAIN LOOP ====
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting Docker watchdog for $URL" >> "$LOG_FILE"
while true; do
  check_url
  sleep "$CHECK_INTERVAL"
done