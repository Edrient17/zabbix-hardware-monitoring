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
zabbix_agentd -t hw.temp.discovery
zabbix_agentd -t 'hw.temp.value_by_id[1]'
zabbix_agentd -t hw.disk.discovery
zabbix_agentd -t hw.memory.ce.count
```

## Zabbix Template

Import `templates/zabbix-hardware-check.yaml` in the Zabbix frontend:

1. Go to `Data collection` -> `Templates`.
2. Click `Import`.
3. Select `templates/zabbix-hardware-check.yaml`.
4. Link `Template Hardware Check` to the monitored host.

The template creates items for agent/tool availability, memory error counts, and low-level discovery prototypes for temperature, fan, PSU, and disk SMART health checks.

Template-level user macros:

- `{$HW_TEMP_WARN}`: temperature warning threshold in Celsius. Default: `80`.
- `{$HW_FAN_MIN_RPM}`: minimum allowed fan RPM. Default: `0`.
- `{$HW_MEMORY_CE_CHANGE_WARN}`: corrected memory error count increase threshold. Default: `0`.
- `{$HW_MEMORY_UE_MAX}`: maximum allowed uncorrected memory error count. Default: `0`.

Override these macros on the linked host when a server model needs different thresholds.

## Ansible Deployment

Use Ansible when deploying the agent files to multiple Linux servers.
The playbook uses the `zabbix_hardware_check` role. It installs `ipmitool`, `smartmontools`, `rasdaemon`, and `sqlite3`, starts `rasdaemon`, deploys the UserParameter files, restarts `zabbix-agent` when needed, and runs basic `zabbix_agentd -t` checks.

```bash
cp ansible/inventory.example.ini ansible/inventory.ini
vi ansible/inventory.ini
ansible-playbook -i ansible/inventory.ini ansible/deploy-hardware-check.yml --check
ansible-playbook -i ansible/inventory.ini ansible/deploy-hardware-check.yml
```

Set `zabbix_agent_include_dir` in the inventory to match the target server's `Include` path.

Useful role variables:

- `hardware_check_install_packages`: install required packages. Default: `true`.
- `hardware_check_manage_rasdaemon`: enable and start `rasdaemon`. Default: `true`.
- `hardware_check_validate`: run `zabbix_agentd -t` checks after deployment. Default: `true`.
- `hardware_check_validate_keys`: UserParameter keys to validate.
