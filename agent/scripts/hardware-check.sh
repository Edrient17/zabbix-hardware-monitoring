#!/bin/sh

set -u

RASDAEMON_DB="${RASDAEMON_DB:-/var/lib/rasdaemon/ras-mc_event.db}"

unsupported() {
    echo "ZBX_NOTSUPPORTED: $*" >&2
    echo "ZBX_NOTSUPPORTED: $*"
    exit 1
}

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || unsupported "$1 not found"
}

run_with_sudo() {
    if [ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null 2>&1; then
        sudo -n "$@" 2>/dev/null || "$@"
    else
        "$@"
    fi
}

tool_exists() {
    command -v "$1" >/dev/null 2>&1 && echo 1 || echo 0
}

ipmi_sensors() {
    need_cmd ipmitool
    run_with_sudo ipmitool sensor 2>/dev/null
}

ipmi_discovery() {
    kind="${1:-all}"

    ipmi_sensors | awk -F '|' -v kind="$kind" '
        function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
        function esc(s) {
            gsub(/\\/, "\\\\", s)
            gsub(/"/, "\\\"", s)
            gsub(/\t/, "\\t", s)
            gsub(/\r/, "", s)
            return s
        }
        function sensor_type(name, unit) {
            n = tolower(name)
            u = tolower(unit)
            if (u ~ /discrete/ || n ~ /redundancy|presence|status|fail|fault/) return "status"
            if (u ~ /degrees c/ || n ~ /temp|thermal|inlet|exhaust|ambient/) return "temperature"
            if (u ~ /rpm/) return "fan"
            if (n ~ /psu|power supply|pwr supply|power unit/) return "psu"
            return "other"
        }
        BEGIN { first = 1; printf "{\"data\":[" }
        NF >= 4 {
            name = trim($1)
            value = trim($2)
            unit = trim($3)
            status = trim($4)
            type = sensor_type(name, unit)

            if (name == "" || value == "na" || value == "disabled") next
            sensor_id++
            if (kind != "" && kind != "all" && kind != type) next

            if (!first) printf ","
            first = 0
            printf "{\"{#SENSOR_ID}\":\"%s\",\"{#SENSOR}\":\"%s\",\"{#SENSOR_TYPE}\":\"%s\",\"{#SENSOR_UNIT}\":\"%s\",\"{#SENSOR_STATUS}\":\"%s\"}", sensor_id, esc(name), esc(type), esc(unit), esc(status)
        }
        END { print "]}" }
    '
}

ipmi_value() {
    sensor="${1:-}"
    [ -n "$sensor" ] || unsupported "missing sensor name"

    value="$(
        ipmi_sensors | awk -F '|' -v wanted="$sensor" '
            function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
            $1 {
                name = trim($1)
                value = trim($2)
                if (name == wanted && value ~ /^[-+]?[0-9]+([.][0-9]+)?$/) {
                    print value + 0
                    exit
                }
            }
        '
    )"

    [ -n "$value" ] || unsupported "IPMI sensor not found or non-numeric: $sensor"
    echo "$value"
}

ipmi_value_by_id() {
    sensor_id="${1:-}"
    [ -n "$sensor_id" ] || unsupported "missing sensor id"

    value="$(
        ipmi_sensors | awk -F '|' -v wanted="$sensor_id" '
            function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
            NF >= 4 {
                name = trim($1)
                value = trim($2)

                if (name == "" || value == "na" || value == "disabled") next
                sensor_id++

                if (sensor_id == wanted && value ~ /^[-+]?[0-9]+([.][0-9]+)?$/) {
                    print value + 0
                    exit
                }
            }
        '
    )"

    [ -n "$value" ] || unsupported "IPMI sensor id not found or non-numeric: $sensor_id"
    echo "$value"
}

ipmi_status() {
    sensor="${1:-}"
    [ -n "$sensor" ] || unsupported "missing sensor name"

    status="$(
        ipmi_sensors | awk -F '|' -v wanted="$sensor" '
            function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
            $1 {
                name = trim($1)
                status = tolower(trim($4))
                if (name == wanted) {
                    if (status == "ok") print 0
                    else print 1
                    exit
                }
            }
        '
    )"

    [ -n "$status" ] || unsupported "IPMI sensor not found: $sensor"
    echo "$status"
}

ipmi_status_by_id() {
    sensor_id="${1:-}"
    [ -n "$sensor_id" ] || unsupported "missing sensor id"

    status="$(
        ipmi_sensors | awk -F '|' -v wanted="$sensor_id" '
            function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
            NF >= 4 {
                name = trim($1)
                value = trim($2)
                status = tolower(trim($4))

                if (name == "" || value == "na" || value == "disabled") next
                sensor_id++

                if (sensor_id == wanted) {
                    if (status == "ok") print 0
                    else print 1
                    exit
                }
            }
        '
    )"

    [ -n "$status" ] || unsupported "IPMI sensor id not found: $sensor_id"
    echo "$status"
}

smart_scan() {
    need_cmd smartctl
    run_with_sudo smartctl --scan-open 2>/dev/null
}

disk_discovery() {
    smart_scan | awk '
        function esc(s) {
            gsub(/\\/, "\\\\", s)
            gsub(/"/, "\\\"", s)
            gsub(/\t/, "\\t", s)
            gsub(/\r/, "", s)
            return s
        }
        BEGIN { first = 1; printf "{\"data\":[" }
        /^\/dev\// {
            dev = $1
            type = "auto"
            for (i = 2; i <= NF; i++) {
                if ($i == "-d" && (i + 1) <= NF) type = $(i + 1)
            }
            disk_id = dev
            if (type != "" && type != "auto") disk_id = dev " " type
            if (!first) printf ","
            first = 0
            printf "{\"{#DISK_ID}\":\"%s\",\"{#DISK}\":\"%s\",\"{#SMART_TYPE}\":\"%s\"}", esc(disk_id), esc(dev), esc(type)
        }
        END { print "]}" }
    '
}

smartctl_for_disk() {
    mode="$1"
    disk="$2"
    smart_type="${3:-auto}"

    need_cmd smartctl
    [ -n "$disk" ] || unsupported "missing disk"

    if [ "$smart_type" = "auto" ] || [ "$smart_type" = "-" ] || [ -z "$smart_type" ]; then
        run_with_sudo smartctl "$mode" "$disk" 2>/dev/null || true
    else
        run_with_sudo smartctl "$mode" -d "$smart_type" "$disk" 2>/dev/null || true
    fi
}

smart_health() {
    disk="${1:-}"
    smart_type="${2:-auto}"
    output="$(smartctl_for_disk -H "$disk" "$smart_type")"

    [ -n "$output" ] || unsupported "empty smartctl health output for $disk"

    echo "$output" | awk '
        BEGIN { result = 2 }
        {
            line = tolower($0)
            if (line ~ /passed|ok/) result = 0
            if (line ~ /failed|failing|failure/) result = 1
        }
        END { print result }
    '
}

smart_attr() {
    disk="${1:-}"
    smart_type="${2:-auto}"
    attr="${3:-}"

    [ -n "$attr" ] || unsupported "missing SMART attribute"
    output="$(smartctl_for_disk -A "$disk" "$smart_type")"

    [ -n "$output" ] || unsupported "empty smartctl attribute output for $disk"

    value="$(
        echo "$output" | awk -v wanted="$attr" '
            function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
            function norm(s) {
                s = tolower(s)
                gsub(/[^a-z0-9]+/, "_", s)
                gsub(/^_+|_+$/, "", s)
                return s
            }
            function first_number(s) {
                if (match(s, /[-+]?[0-9]+([.][0-9]+)?/)) return substr(s, RSTART, RLENGTH)
                return ""
            }
            BEGIN {
                wanted_l = tolower(wanted)
                wanted_n = norm(wanted)
            }
            $1 ~ /^[0-9]+$/ {
                name = $2
                raw = $10
                if ($1 == wanted || tolower(name) == wanted_l || norm(name) == wanted_n) {
                    print first_number(raw)
                    exit
                }
            }
            /:/ {
                name = trim(substr($0, 1, index($0, ":") - 1))
                raw = trim(substr($0, index($0, ":") + 1))
                if (tolower(name) == wanted_l || norm(name) == wanted_n) {
                    print first_number(raw)
                    exit
                }
            }
        '
    )"

    [ -n "$value" ] || unsupported "SMART attribute not found: $disk $attr"
    echo "$value"
}

ras_summary() {
    need_cmd ras-mc-ctl
    ras-mc-ctl --summary 2>/dev/null || unsupported "ras-mc-ctl --summary failed"
}

sqlite_mc_count() {
    mode="$1"

    command -v sqlite3 >/dev/null 2>&1 || return 1
    [ -r "$RASDAEMON_DB" ] || return 1

    tables="$(sqlite3 "$RASDAEMON_DB" ".tables" 2>/dev/null || true)"
    echo "$tables" | grep -qw mc_event || return 1

    columns="$(sqlite3 "$RASDAEMON_DB" "PRAGMA table_info(mc_event);" 2>/dev/null || true)"
    echo "$columns" | grep -q '|err_type|' || return 1

    if echo "$columns" | grep -q '|err_count|'; then
        select_expr="coalesce(sum(cast(err_count as integer)), 0)"
    else
        select_expr="count(*)"
    fi

    if [ "$mode" = "ce" ]; then
        where_expr="(lower(coalesce(err_type,'')) like '%corrected%' or lower(coalesce(err_type,'')) like '%correctable%') and lower(coalesce(err_type,'')) not like '%uncorrect%'"
    else
        where_expr="lower(coalesce(err_type,'')) like '%uncorrect%' or lower(coalesce(err_type,'')) like '%fatal%'"
    fi

    sqlite3 "$RASDAEMON_DB" "select $select_expr from mc_event where $where_expr;" 2>/dev/null
}

summary_mc_count() {
    mode="$1"

    ras_summary | awk -v mode="$mode" '
        {
            line = tolower($0)
            matched = 0
            if (mode == "ce" && line ~ /(corrected|correctable)/ && line !~ /uncorrect/) matched = 1
            if (mode == "ue" && line ~ /(uncorrected|uncorrectable|fatal)/) matched = 1
            if (matched) {
                while (match(line, /[0-9]+/)) {
                    sum += substr(line, RSTART, RLENGTH)
                    line = substr(line, RSTART + RLENGTH)
                }
            }
        }
        END { print sum + 0 }
    '
}

memory_error_count() {
    mode="$1"
    count="$(sqlite_mc_count "$mode" || true)"

    if [ -n "$count" ]; then
        echo "$count"
    else
        summary_mc_count "$mode" 2>/dev/null || echo 0
    fi
}

usage() {
    cat <<'EOF'
Usage: hardware-check.sh <command> [args]

Commands:
  tool <ipmitool|smartctl|ras-mc-ctl>
  ipmi-discovery [all|temperature|fan|psu|status]
  ipmi-value <sensor-name>
  ipmi-value-by-id <sensor-id>
  ipmi-status <sensor-name>
  ipmi-status-by-id <sensor-id>
  disk-discovery
  smart-health <disk> [smart-type]
  smart-attr <disk> [smart-type] <attribute-id-or-name>
  memory-ce-count
  memory-ue-count
EOF
}

command="${1:-}"
shift || true

case "$command" in
    tool)
        tool_exists "${1:-}"
        ;;
    ipmi-discovery)
        ipmi_discovery "${1:-all}"
        ;;
    ipmi-value)
        ipmi_value "${1:-}"
        ;;
    ipmi-value-by-id)
        ipmi_value_by_id "${1:-}"
        ;;
    ipmi-status)
        ipmi_status "${1:-}"
        ;;
    ipmi-status-by-id)
        ipmi_status_by_id "${1:-}"
        ;;
    disk-discovery)
        disk_discovery
        ;;
    smart-health)
        smart_health "${1:-}" "${2:-auto}"
        ;;
    smart-attr)
        smart_attr "${1:-}" "${2:-auto}" "${3:-}"
        ;;
    memory-ce-count)
        memory_error_count ce
        ;;
    memory-ue-count)
        memory_error_count ue
        ;;
    ""|help|-h|--help)
        usage
        ;;
    *)
        unsupported "unknown command: $command"
        ;;
esac
