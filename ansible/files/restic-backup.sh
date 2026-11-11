#!/usr/bin/env bash
# Nightly restic backup of akmon to g72-backup. Managed by Ansible (ansible/backup.yml).
set -euo pipefail

set -a
. /etc/restic/restic.env
set +a

CONTAINERS=(grafana jellyfin portainer npm pihole)
K3S_UNIT=k3s
BACKUP_PATHS=(
  /srv/grafana
  /srv/jellyfin/config
  /srv/npm
  /srv/pihole
  /srv/portainer
  /home/boss/homeserver
  /etc/rancher/k3s
  /var/lib/rancher/k3s/server
)
TEXTFILE_DIR=/var/lib/node_exporter/textfile
STATE_DIR=/var/lib/restic-backup

STARTED_AT=$(date +%s)
SUCCESS=0
SERVICE_FAIL=0
SERVICES_STARTED=0
STOPPED=()
K3S_STOPPED=0

log() { echo "$(date '+%F %T') $*"; }

write_metrics() {
  local now last_success tmp
  now=$(date +%s)
  mkdir -p "$STATE_DIR" "$TEXTFILE_DIR"
  if [ "$SUCCESS" -eq 1 ]; then
    echo "$now" > "$STATE_DIR/last_success"
  fi
  last_success=$(cat "$STATE_DIR/last_success" 2>/dev/null || echo 0)
  tmp=$(mktemp "$TEXTFILE_DIR/backup.prom.XXXXXX")
  cat > "$tmp" <<EOF
# HELP restic_backup_last_run_success 1 if the last backup run succeeded, 0 if it failed.
# TYPE restic_backup_last_run_success gauge
restic_backup_last_run_success $SUCCESS
# HELP restic_backup_last_success_timestamp_seconds Unix time of the last successful backup run.
# TYPE restic_backup_last_success_timestamp_seconds gauge
restic_backup_last_success_timestamp_seconds $last_success
# HELP restic_backup_last_run_duration_seconds Duration of the last backup run.
# TYPE restic_backup_last_run_duration_seconds gauge
restic_backup_last_run_duration_seconds $((now - STARTED_AT))
EOF
  chmod 644 "$tmp"
  mv "$tmp" "$TEXTFILE_DIR/backup.prom"
}

start_services() {
  if [ "$SERVICES_STARTED" -eq 1 ]; then return 0; fi
  SERVICES_STARTED=1
  if [ "$K3S_STOPPED" -eq 1 ]; then
    log "Starting $K3S_UNIT"
    systemctl start "$K3S_UNIT" || { log "ERROR: could not start $K3S_UNIT"; SERVICE_FAIL=1; }
  fi
  local c
  for c in "${STOPPED[@]}"; do
    log "Starting $c"
    docker start "$c" >/dev/null || { log "ERROR: could not start $c"; SERVICE_FAIL=1; }
  done
}

cleanup() {
  start_services
  write_metrics
}
# Pre-flight: exit before touching any service if the backup target is off or unreachable
log "Pre-flight check of the backup repository"
if ! timeout 60 restic cat config >/dev/null 2>&1; then
  log "Backup target unreachable or repository unreadable; nothing was stopped"
  exit 3
fi
 
trap cleanup EXIT

log "Stopping services for a consistent copy"
for c in "${CONTAINERS[@]}"; do
  if [ "$(docker inspect -f '{{.State.Running}}' "$c" 2>/dev/null || true)" = "true" ]; then
    STOPPED+=("$c")
    docker stop -t 30 "$c" >/dev/null
  fi
done
if systemctl is-active --quiet "$K3S_UNIT"; then
  K3S_STOPPED=1
  systemctl stop "$K3S_UNIT"
fi

log "restic backup"
restic backup --tag nightly --exclude-caches "${BACKUP_PATHS[@]}"

start_services

log "restic forget and prune"
restic forget --tag nightly --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --prune

log "restic check"
restic check

if [ "$SERVICE_FAIL" -ne 0 ]; then
  exit 1
fi
SUCCESS=1
log "Backup finished"
