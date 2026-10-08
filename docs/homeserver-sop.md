# T430 Home Server: Operations Guide (SOP)

## 1. Overview

| Item | Value |
|---|---|
| Server | Lenovo ThinkPad T430, hostname `akmon` |
| OS | Debian 13, headless (no desktop) |
| IP | `192.168.1.32` (reserved on the router by MAC address) |
| User | `boss` (sudo). SSH is key-only, root login disabled |
| Control machine | Linux Mint desktop (Ansible, kubectl, git live here) |
| Repo | GitHub `t430-homeserver` (private), local copy `~/t430-homeserver` on Mint |

Rule: a VPN on Mint blocks access to the home network. Disconnect it or enable "allow local network" before using anything below.

## 2. Services and addresses

| Service | Address | Notes |
|---|---|---|
| Jellyfin | `http://192.168.1.32:8096` | Use the IP on TVs. Movies `/data/movies`, music `/data/music` |
| Samba share | `smb://akmon.local/media` | User `boss`. Password is in `~/homeserver/.env` and your password manager |
| Grafana | `http://akmon.local:3000` | Dashboard "Node Exporter Full" (ID 1860), Telegram alerts |
| Prometheus | `http://akmon.local:9090` | Targets page: `/targets` |
| Portainer | `https://akmon.local:9443` | Docker and k3s in one UI. LAN only, never port-forward |
| Nginx Proxy Manager | `http://akmon.local:81` | Installed, not in active use |
| k3s API | `https://192.168.1.32:6443` | Used by `kubectl` on Mint |

Containers (7): jellyfin, samba, npm, node-exporter, prometheus, grafana, portainer.

## 3. Where things live

| What | Path (on the T430) |
|---|---|
| Main compose file and `.env` | `~/homeserver/` |
| Portainer compose file | `~/homeserver/portainer/` |
| Media | `/srv/media/movies`, `/srv/media/music`, `/srv/media/anime` |
| Jellyfin config | `/srv/jellyfin/config` |
| Prometheus config and data | `/srv/prometheus/config/prometheus.yml`, `/srv/prometheus/data`. Repo copy of the config: `ansible/files/prometheus.yml` |
| Grafana data | `/srv/grafana/data` (owned by UID 472, do not change) |
| k3s kubeconfig | `/etc/rancher/k3s/k3s.yaml` (on Mint: `~/.kube/config`) |
| Playbooks (on Mint) | `~/t430-homeserver/ansible/` (`site.yml`, `k3s.yml`, `portainer.yml`) |

## 4. Everyday commands

Connect: `ssh boss@akmon.local` (or `ssh boss@192.168.1.32` if the name does not resolve).

### System

| Command | What it does |
|---|---|
| `uptime` | Time since last boot, load average |
| `free -h` | RAM and swap usage |
| `df -h /srv` | Free disk space (SSD is 224 GB) |
| `ip -4 a` | Shows the server's IP address |
| `sudo reboot` | Restart the server |
| `sudo poweroff` | Safe shutdown. Always use this, never hold the power button |
| `sudo apt update && sudo apt upgrade -y` | Install OS updates. Reboot after kernel updates |
| `sudo systemctl status docker` | Is a service running? (also `k3s`, `ssh`, `fail2ban`) |
| `sudo journalctl -u k3s --since "1 hour ago"` | Recent logs of a service |
| `sudo fail2ban-client status sshd` | Banned IPs and failed SSH attempts |
| `sudo fail2ban-client set sshd unbanip IP` | Unban an IP (for example yourself) |

### Docker (run in `~/homeserver` for the main stack)

| Command | What it does |
|---|---|
| `docker ps` | Running containers and their status |
| `docker ps -a` | All containers, including stopped or crashed ones |
| `docker logs NAME --tail 50` | Last 50 log lines of a container |
| `docker restart NAME` | Restart one container |
| `docker compose up -d` | Start everything in the compose file, apply file changes |
| `docker compose down` | Stop and remove containers (data in `/srv` is kept) |
| `docker compose pull` | Download newer images (then run `up -d`) |
| `docker stats --no-stream` | CPU and RAM per container |
| `docker system df` | Disk used by Docker |
| `docker image prune` | Delete unused images to free space |

### Kubernetes (on Mint; on the T430 prefix with `sudo k3s`)

| Command | What it does |
|---|---|
| `kubectl get nodes` | Node status (expect `Ready`) |
| `kubectl get pods -A` | All pods in all namespaces |
| `kubectl describe pod NAME` | Details and events for a pod |
| `kubectl logs NAME` | Pod logs |
| `kubectl delete deployment NAME` | Remove a deployment |

### Ansible and git (on Mint, in `~/t430-homeserver/ansible`)

| Command | What it does |
|---|---|
| `ansible homeserver -i hosts.ini -m ping` | Test the connection to the server |
| `ansible-playbook -i hosts.ini site.yml -K --check --diff` | Dry run: shows what would change, changes nothing |
| `ansible-playbook -i hosts.ini site.yml -K` | Apply. `-K` asks for the `boss` sudo password |
| `git add . && git commit -m "message" && git push` | Save changes to GitHub |

Playbooks: `site.yml` (OS, Docker, fail2ban, stack), `k3s.yml` (Kubernetes), `portainer.yml` (Portainer and k3s agent).

## 5. Power loss or reboot: bring everything back

Docker, k3s, ssh, fail2ban and avahi start at boot, and containers use `restart: unless-stopped`, so most things return on their own.

1. Power on. If the laptop stayed off after the outage, press the power button.
2. Wait about 3 minutes. From Mint (VPN off): `ping 192.168.1.32`.
3. `ssh boss@akmon.local`
4. Check services: `systemctl is-active docker k3s ssh fail2ban avahi-daemon` (all should say `active`).
5. Check containers: `docker ps`. Expect 7 running.
6. If any are missing:
   - `cd ~/homeserver && docker compose up -d`
   - `cd ~/homeserver/portainer && docker compose up -d`
7. Check Kubernetes from Mint: `kubectl get nodes` (`Ready`). If not, on the T430: `sudo systemctl restart k3s`.
8. Verify:
   - Prometheus targets page: both `prometheus` and `node` are UP
   - Jellyfin loads and plays
   - Samba share mounts
   - Grafana alerts will message you if something is still down

Prevent surprises (not confirmed as configured in this build, check them):
- **Lid close:** by default a Debian laptop suspends when the lid closes. Set `HandleLidSwitch=ignore` and `HandleLidSwitchExternalPower=ignore` in `/etc/systemd/logind.conf`, then reboot.
- **BIOS (F1 at boot):** look for an option like "Power-On with AC Attach" so it starts by itself when power returns.
- The battery acts as a short backup. A long outage that drains it needs the manual power-on above.

## 6. Updates

- **OS:** `sudo apt update && sudo apt upgrade -y`, then `sudo reboot` if the kernel changed.
- **Containers:** `cd ~/homeserver && docker compose pull && docker compose up -d`. Images use `latest`, so an update can change behavior. Check `docker ps` and Grafana afterwards.
- **Changing the stack:** edit `~/t430-homeserver/ansible/files/docker-compose.yml` on Mint, run the playbook, commit and push. Do not edit the file by hand on the server.

## 7. Troubleshooting

| Symptom | Likely cause and fix |
|---|---|
| Nothing on the server reachable from Mint | VPN is on. Disconnect or allow local network. Then `ping 192.168.1.32` |
| `akmon.local` does not resolve (TVs, phones) | Use the IP `192.168.1.32` instead |
| `Permission denied (publickey)` on SSH | Wrong key or different user. Test `ssh -v boss@akmon.local`. Try the IP |
| Samba: cannot write to `movies` or `music` | Run `docker restart samba` (re-applies ownership). The playbook must not set owner or mode on those folders |
| Samba login fails | Wrong password. Clear the saved one in the Mint keyring and retype |
| Jellyfin does not show new files | Dashboard, Libraries, Scan All Libraries. Check the folder is mounted: `docker exec jellyfin ls /data` |
| Jellyfin "fatal error" with subtitles | Image-based or `.ass` subtitles force a burn-in transcode. Use a text `.srt` track, or play with subtitles off |
| Video stutters | HEVC cannot be hardware-decoded on this GPU (HD4000: H.264 only). Prefer H.264 files |
| Grafana shows no data | Prometheus `/targets` page: if `node` is down, check `docker ps` for node-exporter |
| Grafana data source error "http server gave http response to https client" | The URL must start with `http://`, not `https://` |
| No Telegram alert | Grafana, Alerting, Contact points, press Test. Check the bot token and chat ID |
| Portainer setup token or 403 | `docker restart portainer`, then `docker logs portainer 2>&1 \| grep setup_token`, use the new token within 5 minutes |
| Disk nearly full | `df -h /srv`, `docker system df`, `docker image prune` |
| A container keeps restarting | `docker logs NAME --tail 50` and read the last error |
| `curl` download from paste.rs is 435 bytes | That is the 404 page. URLs are case-sensitive, so retype exactly |
| TV or monitor cannot connect to Jellyfin | Use `http://192.168.1.32:8096` (IP, `http`, port 8096) and make sure the device is on the same network as the server |

## 8. Rebuild from scratch (SSD failure or reinstall)

1. Install Debian 13 netinst, headless: hostname `akmon`, user `boss` with sudo, root password blank, SSH server selected.
2. The router reservation for `192.168.1.32` is tied to the laptop's MAC, so it stays the same.
3. From Mint: `ssh-copy-id boss@akmon.local`. If a host key warning appears: `ssh-keygen -R akmon.local`.
4. On the T430, recreate `~/homeserver/.env` containing `SAMBA_PASSWORD=...` (password from your password manager).
5. On Mint: `cd ~/t430-homeserver/ansible`, then run `site.yml`, `k3s.yml` and `portainer.yml` in that order.
6. Copy `prometheus.yml` from the repo to the server, then restart Prometheus. From `~/t430-homeserver` on Mint: `scp ansible/files/prometheus.yml boss@akmon.local:/tmp/` then on the T430 `sudo cp /tmp/prometheus.yml /srv/prometheus/config/prometheus.yml && docker restart prometheus`.
7. On Mint, re-fetch the kubeconfig: `ssh boss@akmon.local "sudo cat /etc/rancher/k3s/k3s.yaml"`, save as `~/.kube/config`, change `127.0.0.1` to `192.168.1.32`, then `chmod 600 ~/.kube/config`.
8. Re-do by hand (data is not backed up): Jellyfin libraries and users, Grafana data source (`http://prometheus:9090`), dashboard 1860, Telegram contact point and alert rules (reference: `grafana/alert-rules.yaml` in the repo), Portainer admin user and environments, and copy the media back.

## 9. Alert rules (Grafana, Telegram)

| Rule | Condition | Pending |
|---|---|---|
| Host down | node target `up` below 1 | 2m |
| Disk usage | root filesystem above 85% | 5m |
| Memory usage | above 90% | 5m |
| CPU temperature | above 85 C | 5m |

Only "Host down" has been tested. Test method: `docker stop node-exporter`, wait about 4 minutes, then `docker start node-exporter`.

## 10. Known gaps and pending items

- **No backups.** Media, Jellyfin config, Grafana and Portainer data exist only on the T430's SSD. This is the highest-priority item.
- **`prometheus.yml` is in the repo but not deployed by a playbook.** It is stored as `ansible/files/prometheus.yml`. A future task in `site.yml` should copy it to `/srv/prometheus/config/`. Until then, step 6 of section 8 is manual. Update the repo copy whenever the live file changes.
- **Lid and BIOS power settings** (section 5) are unconfirmed.
- **Only the "Host down" alert has been tested.** Test the disk, memory and temperature rules.
- **Container alerts** (container down) are not possible with node-exporter alone and would need cAdvisor.
- **Repo commit author email** is the personal one. This was accepted. Change it only if the decision changes.

Done: Samba password moved to `.env`, anime library running, Samsung M7 monitor connected.

Passwords and tokens (Samba, Grafana admin, Portainer, Telegram bot token) are not stored in this document or in git. Keep them in a password manager.
