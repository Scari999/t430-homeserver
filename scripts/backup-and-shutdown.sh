#!/usr/bin/env bash
# Run the akmon backup on demand, then shut the G72 down.
# Run this on the control machine, with the VPN off and the G72 powered on.
set -u

AKMON=boss@akmon.local
G72=boss@192.168.1.5

echo "Checking that the G72 is reachable..."
if ! ssh -o ConnectTimeout=5 -o BatchMode=yes "$G72" true; then
  echo "The G72 is not reachable. Power it on, wait a minute, and run this again." >&2
  exit 1
fi

echo "Running the backup on akmon (sudo password of boss on akmon)..."
if ssh -t "$AKMON" 'sudo systemctl start restic-backup.service'; then
  echo "Backup finished successfully."
else
  echo "Backup FAILED. The G72 stays on. Logs: ssh -t $AKMON 'sudo journalctl -u restic-backup.service -n 40 --no-pager'" >&2
  exit 2
fi

echo "Shutting down the G72 (sudo password of boss on the G72)..."
ssh -t "$G72" 'sudo systemctl poweroff'
echo "Done."
