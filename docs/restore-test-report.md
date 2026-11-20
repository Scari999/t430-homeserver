# Restore test report

A backup is only useful if it can be restored. This page shows what I restored, how long it took, and how I checked that the restored data was correct.

## What I set up

- The home server (`akmon`, the T430) backs up to a second computer (an HP G72) with [Restic](https://restic.net/).
- The setup is automated with Ansible (`ansible/backup.yml` and `ansible/backup-target.yml`), so it can be repeated.
- A backup runs with one command from my desktop: `scripts/backup-and-shutdown.sh`. It backs up the server, then shuts the second computer down.
- Everything is encrypted. The password is stored outside GitHub.
- Backed up: Grafana, Jellyfin, Pi-hole, Nginx Proxy Manager, Portainer, Kubernetes (k3s) and the Docker Compose and `.env` files. Not backed up on purpose: the media library (large, can be copied again) and the monitoring history.

## Size and speed

| | Result |
|---|---|
| Size of one backup copy | about 600 MB of data |
| First backup | 52 seconds. The first copy stored 246 MB after compression |
| Later backups | 28 to 38 seconds |
| Space used on the backup computer | 373 MB for 4 backup copies |
| Services stopped during a backup | about 1 minute, so the files are copied in a consistent state |

## What I restored

| Test | Date | Restored | Where | Time |
|---|---|---|---|---|
| Everything | 2026-11-05 | All backed up data (2,090 files, 600 MB) | A temporary folder on the server | 26 seconds |
| One service on another computer | 2026-11-05 | Grafana (510 MB) | The second computer, started in Docker | 5 seconds |
| One file | 2026-11-11 | `docker-compose.yml`, restored in two different ways | A temporary folder, and straight to a file | 1.4 seconds |
| One service in place | 2026-11-11 | Grafana (510 MB), replacing the running copy | The server | 19 seconds (Grafana was stopped for 67 seconds) |

## How I checked the restored data

- **File owners.** Restored files kept the same owners as the originals (for example, Grafana's files belong to user 472).
- **File comparison.** The restored Docker Compose files, `.env` files and k3s settings matched the originals exactly. The restored single file matched byte for byte, in both methods.
- **Databases.** Nine databases were found in the restored data (Grafana, Jellyfin, Nginx Proxy Manager, four from Pi-hole and the k3s database). All nine passed SQLite's built-in integrity check.
- **Running service.** Grafana started from the restored data on the second computer and showed its restored dashboard and settings. Restored in place on the server, it reported a healthy status (`"database": "ok"`).
- **Alerts.** I made a fake "backup failed" and "no backup for 30 days" state. Both Grafana alerts fired and the Telegram messages arrived.
- **Backup computer switched off.** I ran the backup with the second computer powered off. The script stopped after 13 seconds without touching any service.

## Problems I ran into and how I fixed them

| Problem | Cause | Fix |
|---|---|---|
| Logging in with the backup key was refused, although the key and permissions were right | The backup user was called `backup`, which is also a built-in Debian account, so the key was looked for in the wrong folder. I found it by running a temporary debug SSH server | Restored the built-in account to its defaults and renamed my user to `akmonbackup` |
| Ansible dry run failed with "field hosts is required" | One misindented line made a second, incomplete play | Fixed the indentation |
| The `docker` command was missing after a minimal install | On Debian 13, `docker-cli` is only a recommended package | Added `docker-cli` to the install list |
| A rebuilt server could not have reached the backup | The SSH key and the trust of the backup computer had been set up by hand, and a missing password file would have created a new password | Ansible now creates the key, trusts the backup computer, and stops with a clear message if the password file is missing |
| Running the main playbook would have removed a monitoring setting | The two copies of the Compose file in the repository lacked two lines I had added on the server | Copied the working file into both places |
