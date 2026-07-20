# zabbix_hardware_check

Deploys Zabbix Agent 1 UserParameter based hardware checks to Linux targets.

## What It Does

- Installs hardware monitoring packages.
- Enables and starts `rasdaemon`.
- Creates the Zabbix Agent include and script directories.
- Copies `hardware-check.conf` and `hardware-check.sh`.
- Restarts `zabbix-agent` when the UserParameter config changes.
- Validates selected keys with `zabbix_agentd -t`.

## Variables

| Variable | Default | Description |
| --- | --- | --- |
| `zabbix_agent_include_dir` | `/etc/zabbix/zabbix_agentd.conf.d` | Target directory included by `zabbix_agentd.conf`. |
| `zabbix_scripts_dir` | `/etc/zabbix/scripts` | Target directory for `hardware-check.sh`. |
| `zabbix_agent_service` | `zabbix-agent` | System service name for Zabbix Agent 1. |
| `hardware_check_install_packages` | `true` | Install required packages with apt. |
| `hardware_check_manage_rasdaemon` | `true` | Enable and start `rasdaemon`. |
| `hardware_check_validate` | `true` | Run post-deploy UserParameter checks. |
| `hardware_check_packages` | see defaults | Package list for the target OS. |
| `hardware_check_validate_keys` | see defaults | Keys checked with `zabbix_agentd -t`. |

## Example

```yaml
---
- name: Deploy Zabbix hardware UserParameter checks
  hosts: hardware_targets
  become: true

  roles:
    - zabbix_hardware_check
```
