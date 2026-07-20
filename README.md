# Zabbix Hardware Monitoring

Local Zabbix Server stack for validating hardware monitoring against a remote Linux server running Zabbix Agent 1 passive checks.

Image versions are pinned through `.env` values instead of floating `latest` tags.

## Services

- PostgreSQL for the Zabbix database
- Zabbix Server with PostgreSQL support
- Zabbix Web UI with nginx

## Start

```bash
cp .env.example .env
docker compose up -d
```

Open the web UI at `http://localhost:8080`.

Default Zabbix login:

- User: `Admin`
- Password: `zabbix`

## Remote Agent Notes

The monitored Linux server should run native Zabbix Agent 1 on port `10050`.

Copy `agent/zabbix_agentd.d/hardware-check.conf` to the remote server's included agent config directory. Common paths are `/etc/zabbix/zabbix_agentd.d/` and `/etc/zabbix/zabbix_agentd.conf.d/`.
Copy `agent/scripts/hardware-check.sh` to the remote server's `/etc/zabbix/scripts/`.

```bash
sudo install -m 0644 agent/zabbix_agentd.d/hardware-check.conf /etc/zabbix/zabbix_agentd.conf.d/hardware-check.conf
sudo install -m 0755 agent/scripts/hardware-check.sh /etc/zabbix/scripts/hardware-check.sh
sudo systemctl restart zabbix-agent
```

Quick checks:

```bash
zabbix_agentd -t hw.agent.ping
zabbix_agentd -t hw.temp.discovery
zabbix_agentd -t 'hw.temp.value_by_id[1]'
zabbix_agentd -t hw.disk.discovery
zabbix_agentd -t hw.memory.ce.count
```
