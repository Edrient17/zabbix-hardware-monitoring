# Installation Guide

This guide explains how to install `Custom Hardware Check` for a Linux server monitored by Zabbix Agent 1 passive checks.

## 1. Prerequisites

Target Linux server:

- Zabbix Agent 1
- Agent passive check port open from Zabbix Server or Proxy, usually `10050/tcp`
- `ipmitool`
- `smartmontools`
- `rasdaemon`
- `sqlite3`

Ubuntu/Debian example:

```bash
sudo apt update
sudo apt install -y zabbix-agent ipmitool smartmontools rasdaemon sqlite3
sudo systemctl enable --now rasdaemon
```

## 2. Import Zabbix Template

Import the template in Zabbix Web UI:

```text
templates/zabbix-hardware-check.yaml
```

Template:

```text
Name: Custom Hardware Check
Group: Templates/Custom/Hardware
```

After import, link `Custom Hardware Check` to the target host.

Review template macros if needed:

- `{$HW_TEMP_WARN}`
- `{$HW_FAN_MIN_RPM}`
- `{$HW_MEMORY_CE_CHANGE_WARN}`
- `{$HW_MEMORY_UE_MAX}`

## 3. Manual Agent Deployment

Copy the UserParameter file:

```text
agent/zabbix_agentd.d/hardware-check.conf
-> /etc/zabbix/zabbix_agentd.conf.d/hardware-check.conf
```

Copy the script:

```text
agent/scripts/hardware-check.sh
-> /etc/zabbix/scripts/hardware-check.sh
```

Apply permissions:

```bash
sudo mkdir -p /etc/zabbix/scripts
sudo chown root:root /etc/zabbix/zabbix_agentd.conf.d/hardware-check.conf
sudo chmod 0644 /etc/zabbix/zabbix_agentd.conf.d/hardware-check.conf
sudo chown root:root /etc/zabbix/scripts/hardware-check.sh
sudo chmod 0755 /etc/zabbix/scripts/hardware-check.sh
sudo systemctl restart zabbix-agent
```

Check the actual Agent include path:

```bash
grep -n '^Include=' /etc/zabbix/zabbix_agentd.conf
```

## 4. Ansible Deployment

Use Ansible for repeatable deployment.

```bash
cp ansible/inventory.example.ini ansible/inventory.ini
vi ansible/inventory.ini
```

Example inventory:

```ini
[hardware_targets]
server01 ansible_host=<target_ip> ansible_user=<ssh_user> ansible_port=1024
```

If the SSH user must switch to root with `su -`, add:

```ini
ansible_become_method=su ansible_become_user=root
```

Test connectivity and privilege escalation:

```bash
ansible -i ansible/inventory.ini hardware_targets -m ping --ask-pass
ansible -i ansible/inventory.ini hardware_targets -m command -a 'id' --ask-pass --ask-become-pass -b
```

Run the playbook:

```bash
ansible-playbook --syntax-check -i ansible/inventory.ini ansible/deploy-hardware-check.yml
ansible-playbook -i ansible/inventory.ini ansible/deploy-hardware-check.yml --ask-pass --ask-become-pass
```

Success criteria:

```text
failed=0
unreachable=0
```

## 5. sudoers Check

The script runs as the `zabbix` user, but some hardware commands may require root privileges.

Check:

```bash
sudo -u zabbix sudo -n ipmitool sensor
sudo -u zabbix sudo -n ipmitool sdr type "Power Supply"
sudo -u zabbix sudo -n smartctl --scan-open
```

If these fail, allow only the required commands with `NOPASSWD` through sudoers.

## 6. Local Validation

Run on the target Linux server:

```bash
zabbix_agentd -t hw.tools.ipmitool
zabbix_agentd -t hw.tools.smartctl
zabbix_agentd -t hw.tools.rasdaemon
zabbix_agentd -t hw.temp.discovery
zabbix_agentd -t hw.fan.discovery
zabbix_agentd -t hw.psu.discovery
zabbix_agentd -t hw.voltage.discovery
zabbix_agentd -t hw.disk.discovery
zabbix_agentd -t hw.memory.ce.count
zabbix_agentd -t hw.memory.ue.count
```

PSU discovery uses:

```bash
ipmitool sdr type "Power Supply"
```

## 7. Zabbix Web Validation

Check Latest data for:

- Tool availability
- Temperature value/status
- Fan RPM/status
- PSU status
- Voltage value/status
- Disk SMART health
- Memory CE/UE count

Check Triggers for:

- ipmitool missing
- smartctl missing
- rasdaemon missing
- PSU status != 0
- SMART health = 1
- Memory UE count > 0
- Memory CE count increased
- Temperature > threshold
- Temperature status != 0
- Fan RPM <= min rpm
- Fan status != 0
- Voltage status != 0

## 8. Cache Cleanup

The script stores IPMI cache files under:

```text
/tmp/hardware-check-ipmi-sensor-<zabbix_uid>/
```

If IPMI discovery gets stuck, clear the cache:

```bash
sudo rm -rf /tmp/hardware-check-ipmi-sensor-*
sudo systemctl restart zabbix-agent
```

