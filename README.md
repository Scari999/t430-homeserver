# T430 Home Media Server

A self-hosted media server and infrastructure learning project, built on a
repurposed Lenovo ThinkPad T430 running headless Debian 13, with a fully
containerized service stack and Ansible-based provisioning.

## Motivation

Built while transitioning from a Technical Support Engineer role toward
SRE / Sysadmin work — a way to get real hands-on practice with Linux
administration, containerization, monitoring, and infrastructure-as-code,
rather than tutorial-only exposure.

## Hardware

- Lenovo ThinkPad T430
- Intel i5-3320M @ 2.60GHz
- 8GB RAM
- 224GB Apacer AS340 SSD
- Intel HD Graphics 4000 (VAAPI hardware transcoding)

## Services

| Service | Purpose | Port(s) |
|---|---|---|
| Jellyfin | Media streaming, VAAPI hardware transcoding | host network |
| Samba | LAN file share for media ingestion | 139, 445 |
| Nginx Proxy Manager | Reverse proxy / future HTTPS termination | 80, 443, 81 |
| Prometheus | Metrics collection | 9090 |
| Grafana | Metrics dashboards | 3000 |
| node-exporter | Host-level hardware metrics | host network |

All services are defined in [`docker-compose.yml`](docker-compose.yml) and
deployed via Docker Compose.

## Provisioning (Ansible)

The full build — OS hardening, Docker install, VAAPI drivers, fail2ban, and
the container stack — is codified in [`ansible/site.yml`](ansible/site.yml).
Any similar Debian machine can be brought to the same state with:

```bash
ansible-playbook -i ansible/hosts.ini ansible/site.yml -K --check --diff   # dry run
ansible-playbook -i ansible/hosts.ini ansible/site.yml -K                  # apply
```

## Security notes

- SSH: key-only authentication, root login disabled
- fail2ban: bans repeated failed SSH login attempts
- Samba credentials in this repo are placeholders (`CHANGEME`) — real
  secrets are never committed to version control. Replace before deploying.

## Debugging write-up

[`docs/samba-yaml-debugging.md`](docs/samba-yaml-debugging.md) — a postmortem
of a multi-hour debugging session tracing a Samba container crash loop to a
YAML parsing quirk in Docker Compose's string-form `command:` field.

## Status / roadmap

Actively maintained homelab. k3s (single-node Kubernetes) is running alongside Docker Compose stack - see ['ansible/k3s.yml'](ansible/k3s.yml). Planned next:  a second node
for multi-host Ansible practice, and a CI pipeline via GitHub Actions.

## Management UI (Portainer)

Portainer runs as a container and manages both environments from one UI:
the local Docker stack and the k3s cluster (via the Portainer agent,
exposed on NodePort 30778). Provisioned by
[`ansible/portainer.yml`](ansible/portainer.yml).

Portainer mounts the Docker socket, which is effectively root access to the
host. Keep port 9443 LAN-only and do not expose it to the internet.
