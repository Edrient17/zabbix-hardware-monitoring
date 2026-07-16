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

The monitored Linux server should run native Zabbix Agent 1 on port `1024`.

Copy `agent/zabbix_agentd.d/hardware-check.conf` to the remote server's `/etc/zabbix/zabbix_agentd.d/`.
Scripts should live in `/etc/zabbix/scripts/` on the remote server if a UserParameter calls them.
