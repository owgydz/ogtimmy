#!/bin/bash

version="2.9.6-rc2"

config_dir="/etc/timmy"
log_dir="/var/log/timmy"
log_file="$log_dir/timmy.log"
image_dir="$HOME/timmy/images"
history_file="$HOME/.timmy_history"
backup_dir="/var/backups/timmy"

mkdir -p "$config_dir" 2>/dev/null
mkdir -p "$log_dir" 2>/dev/null
mkdir -p "$image_dir" 2>/dev/null
mkdir -p "$backup_dir" 2>/dev/null

boot_session=$(date +%Y%m%d_%H%M%S)
session_log="$log_dir/session_$boot_session.log"

error_count=0
verbose_mode=0
pager_mode=0

for arg in "$@"; do

    case "$arg" in

        --verbose|-v)
            verbose_mode=1
            ;;

        --scroll|-s)
            pager_mode=1
            ;;

    esac
done

red="\e[31m"
green="\e[32m"
yellow="\e[33m"
blue="\e[34m"
cyan="\e[36m"
white="\e[97m"
reset="\e[0m"

record_history() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') | $*" >> "$history_file"
}

record_history "$@"

page_output() {

    if [ "$pager_mode" -eq 1 ]; then

        less \
            -R \
            -M \
            -i \
            -J \
            -+F \
            -X

    else
        cat
    fi
}

verbose_print() {

    if [ "$verbose_mode" -eq 1 ]; then
        printf "${blue}[verbose]${reset} %s\n" "$1"
    fi
}

log_system() {

    subsystem="$1"
    message="$2"

    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    log_entry="[$timestamp][$subsystem] $message"

    echo "$log_entry" >> "$log_file"
    echo "$log_entry" >> "$session_log"

    printf "${cyan}[log]${reset} %s\n" "$log_entry"

    if [ "$verbose_mode" -eq 1 ]; then
        printf "${blue}[verbose-log]${reset} %s\n" "$log_entry"
    fi
}

log_info() {
    log_system "info" "$1"
}

log_warn() {
    log_system "warn" "$1"
}

log_error() {
    error_count=$((error_count + 1))
    log_system "fail" "$1"
}

line() {
    printf "${blue}====================================================${reset}\n"
}

header() {

    if [ "$pager_mode" -eq 0 ]; then
        clear
    fi

    printf "${cyan}"
    printf "████████╗██╗███╗   ███╗███╗   ███╗██╗   ██╗\n"
    printf "╚══██╔══╝██║████╗ ████║████╗ ████║╚██╗ ██╔╝\n"
    printf "   ██║   ██║██╔████╔██║██╔████╔██║ ╚████╔╝ \n"
    printf "   ██║   ██║██║╚██╔╝██║██║╚██╔╝██║  ╚██╔╝  \n"
    printf "   ██║   ██║██║ ╚═╝ ██║██║ ╚═╝ ██║   ██║   \n"
    printf "   ╚═╝   ╚═╝╚═╝     ╚═╝╚═╝     ╚═╝   ╚═╝   \n"
    printf "${reset}"

    line
    printf "${cyan} timmy engineering console v%s ${reset}\n" "$version"
    line
}

loading() {

    msg="$1"

    printf "${yellow}[timmy]${reset} %s" "$msg"

    for i in {1..3}; do
        sleep 0.15
        printf "."
    done

    printf "\n"

    log_info "$msg"
}

ok() {
    printf "${green}[ ok ]${reset} %s\n" "$1"
    log_info "$1"
}

warn() {
    printf "${yellow}[warn]${reset} %s\n" "$1"
    log_warn "$1"
}

err() {
    printf "${red}[fail]${reset} %s\n" "$1"
    log_error "$1"
}

require_root() {

    if [ "$EUID" -ne 0 ]; then
        err "root privileges required"
        exit 1
    fi
}

unsafe_check() {

    if [ ! -f "$config_dir/unsafe.conf" ]; then
        err "unsafe mode disabled"
        exit 1
    fi
}

fetch_cleanup() {

    required_mb="$1"

    available_mb=$(df -Pm "$image_dir" | awk 'NR==2 {print $4}')

    verbose_print "required space: ${required_mb}mb"
    verbose_print "available space: ${available_mb}mb"

    if [ "$available_mb" -ge "$required_mb" ]; then
        return
    fi

    warn "insufficient storage space detected"

    echo
    printf "${yellow}cached images marked for deletion:${reset}\n\n"

    total_reclaim=0

    while read -r file; do

        [ -f "$file" ] || continue

        size_mb=$(du -m "$file" | awk '{print $1}')
        total_reclaim=$((total_reclaim + size_mb))

        printf " %-8s %s\n" "${size_mb}mb" "$file"

    done < <(find "$image_dir" -type f)

    echo
    printf " reclaimable space : %smb\n\n" "$total_reclaim"

    printf "${yellow}delete cached images to continue? [y/N]: ${reset}"
    read confirm

    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        err "download aborted"
        exit 1
    fi

    verbose_print "deleting cached images"

    find "$image_dir" -type f | while read -r file; do

        verbose_print "deleting $file"

        rm -f "$file"
    done

    ok "cached images deleted"

    available_mb=$(df -Pm "$image_dir" | awk 'NR==2 {print $4}')

    verbose_print "remaining free space: ${available_mb}mb"

    if [ "$available_mb" -lt "$required_mb" ]; then
        err "still insufficient storage space"
        exit 1
    fi
}

bar_graph() {

    percent="$1"

    filled=$((percent / 10))
    empty=$((10 - filled))

    printf "["

    for ((i=0;i<filled;i++)); do
        printf "█"
    done

    for ((i=0;i<empty;i++)); do
        printf "░"
    done

    printf "]"
}

status_cmd() {

    header

    printf "${white}system status${reset}\n\n"

    hostname_value=$(hostname)
    kernel_value=$(uname -r)
    arch_value=$(uname -m)
    uptime_value=$(uptime -p)
    memory_value=$(free -h | awk '/Mem:/ {print $3 " / " $2}')

    printf " hostname      : %s\n" "$hostname_value"
    printf " kernel        : %s\n" "$kernel_value"
    printf " architecture  : %s\n" "$arch_value"
    printf " uptime        : %s\n" "$uptime_value"
    printf " memory        : %s\n" "$memory_value"

    if [ -d /sys/class/power_supply/BAT0 ]; then
        battery_value=$(cat /sys/class/power_supply/BAT0/capacity)
        printf " battery       : %s%%\n" "$battery_value"
    fi

    echo

    if [ "$verbose_mode" -eq 1 ]; then

        verbose_print "detailed system information"

        verbose_print "hostname: $hostname_value"
        verbose_print "kernel: $kernel_value"
        verbose_print "architecture: $arch_value"

        verbose_print "cpu info"

        lscpu | while read -r line; do
            verbose_print "$line"
        done

        verbose_print "memory info"

        free -h | while read -r line; do
            verbose_print "$line"
        done

        verbose_print "mounted filesystems"

        mount | while read -r line; do
            verbose_print "$line"
        done
    fi
}

monitor_cmd() {

    while true; do

        if [ "$pager_mode" -eq 0 ]; then
            clear
        fi

        cpu_usage=$(top -bn1 | awk '/Cpu/ {print 100 - $8}')
        cpu=$(printf "%.0f" "$cpu_usage")

        ram_percent=$(free | awk '/Mem:/ {printf("%.0f"), $3/$2 * 100}')
        disk_percent=$(df / | awk 'NR==2 {print $5}' | tr -d '%')

        temp=0

        if [ -f /sys/class/thermal/thermal_zone0/temp ]; then
            temp=$(( $(cat /sys/class/thermal/thermal_zone0/temp) / 1000 ))
        fi

        header

        printf " cpu   "
        bar_graph "$cpu"
        printf " %s%%\n" "$cpu"

        printf " ram   "
        bar_graph "$ram_percent"
        printf " %s%%\n" "$ram_percent"

        printf " disk  "
        bar_graph "$disk_percent"
        printf " %s%%\n" "$disk_percent"

        printf " temp  "
        bar_graph "$temp"
        printf " %sc\n" "$temp"

        echo
        printf " errors logged : %s\n" "$error_count"

        if [ "$verbose_mode" -eq 1 ]; then
            verbose_print "live cpu usage : ${cpu}%"
            verbose_print "live ram usage : ${ram_percent}%"
            verbose_print "live disk usage: ${disk_percent}%"
            verbose_print "live temp      : ${temp}c"
        fi

        sleep 2
    done
}

hardware_scan() {

    header

    printf "${white}hardware scanner${reset}\n\n"

    echo "[cpu]"
    lscpu | page_output

    echo
    echo "[memory]"
    free -h | page_output

    echo
    echo "[storage]"
    lsblk | page_output

    echo
    echo "[pci]"
    lspci | page_output

    echo
    echo "[usb]"
    lsusb | page_output

    echo
    echo "[audio]"
    lspci | grep -i audio | page_output

    echo

    if [ "$verbose_mode" -eq 1 ]; then

        verbose_print "dmi information"

        dmidecode 2>/dev/null | while read -r line; do
            verbose_print "$line"
        done
    fi
}

benchmark_cmd() {

    header

    printf "${white}advanced benchmark suite${reset}\n\n"

    cpu_model=$(grep "model name" /proc/cpuinfo | head -1 | cut -d: -f2 | sed 's/^ //')
    cpu_cores=$(nproc)
    total_mem=$(free -h | awk '/Mem:/ {print $2}')
    disk_model=$(lsblk -d -o NAME,SIZE | tail -n +2)

    printf " cpu model     : %s\n" "$cpu_model"
    printf " cpu cores     : %s\n" "$cpu_cores"
    printf " memory total  : %s\n" "$total_mem"

    echo

    verbose_print "detected disk devices:"
    verbose_print "$disk_model"

    loading "running cpu benchmark"

    cpu_start=$(date +%s%N)

    sha256sum /dev/zero >/dev/null &
    cpu_pid=$!

    for i in {1..8}; do

        if [ "$verbose_mode" -eq 1 ]; then

            cpu_live=$(top -bn1 | awk '/Cpu/ {print 100 - $8}')
            cpu_temp=0

            if [ -f /sys/class/thermal/thermal_zone0/temp ]; then
                cpu_temp=$(( $(cat /sys/class/thermal/thermal_zone0/temp) / 1000 ))
            fi

            verbose_print "cpu load ${cpu_live}% | temp ${cpu_temp}c"
        fi

        sleep 1
    done

    kill "$cpu_pid" 2>/dev/null

    cpu_end=$(date +%s%N)
    cpu_runtime=$(( (cpu_end - cpu_start) / 1000000 ))

    ok "cpu benchmark completed"

    loading "running memory benchmark"

    mem_start=$(date +%s%N)

    dd if=/dev/zero of=/tmp/timmy_memtest bs=1M count=2048 status=progress

    sync

    mem_end=$(date +%s%N)

    mem_runtime=$(( (mem_end - mem_start) / 1000000 ))
    mem_speed=$((2048 * 1000 / (mem_runtime / 1000 + 1)))

    rm -f /tmp/timmy_memtest

    ok "memory benchmark completed"

    loading "running disk benchmark"

    disk_start=$(date +%s%N)

    dd if=/dev/zero of=/tmp/timmy_disk_test bs=8M count=256 conv=fdatasync status=progress

    disk_end=$(date +%s%N)

    disk_runtime=$(( (disk_end - disk_start) / 1000000 ))
    disk_speed=$((2048 * 1000 / (disk_runtime / 1000 + 1)))

    rm -f /tmp/timmy_disk_test

    ok "disk benchmark completed"

    echo

    printf "${cyan}benchmark results${reset}\n\n"

    printf " cpu runtime : %sms\n" "$cpu_runtime"

    echo
}

network_scan() {

    header

    ip addr | page_output
}

network_ping() {

    target="$3"

    header

    verbose_print "target host: $target"

    ping -c 4 "$target" | page_output

    if [ "$verbose_mode" -eq 1 ]; then

        verbose_print "dns lookup"

        getent hosts "$target" | while read -r line; do
            verbose_print "$line"
        done
    fi
}

network_trace() {

    target="$3"

    header

    verbose_print "trace target: $target"

    traceroute "$target" | page_output
}

network_ports() {

    header

    ss -tulpn | page_output

    if [ "$verbose_mode" -eq 1 ]; then
        verbose_print "active listening services displayed"
    fi
}

network_wifi_scan() {

    header

    verbose_print "scanning nearby wifi networks"

    if command -v nmcli >/dev/null 2>&1; then
        nmcli dev wifi | page_output
    else
        iw dev wlan0 scan | page_output
    fi
}

network_speedtest() {

    loading "running speed test"

    verbose_print "target host: speed.hetzner.de"

    start=$(date +%s)

    curl -L -o /dev/null https://speed.hetzner.de/100MB.bin

    end=$(date +%s)

    runtime=$((end - start))

    printf "\n download completed in %ss\n\n" "$runtime"
}

network_sniff() {

    unsafe_check

    verbose_print "capturing packets on all interfaces"

    tcpdump -i any
}

thermal_cmd() {

    header

    for zone in /sys/class/thermal/thermal_zone*; do

        if [ -f "$zone/temp" ]; then

            name=$(cat "$zone/type")
            temp=$(cat "$zone/temp")
            celsius=$((temp / 1000))

            printf " %-15s : %sc\n" "$name" "$celsius"

            if [ "$verbose_mode" -eq 1 ]; then
                verbose_print "raw thermal value for $name : ${temp}mc"
            fi
        fi
    done

    echo
}

battery_health() {

    header

    capacity=$(cat /sys/class/power_supply/BAT0/capacity 2>/dev/null)
    status=$(cat /sys/class/power_supply/BAT0/status 2>/dev/null)

    printf " capacity : %s%%\n" "$capacity"
    printf " status   : %s\n" "$status"

    echo

    if [ "$verbose_mode" -eq 1 ]; then

        verbose_print "battery telemetry"

        for file in /sys/class/power_supply/BAT0/*; do

            if [ -f "$file" ]; then

                name=$(basename "$file")
                value=$(cat "$file" 2>/dev/null)

                verbose_print "$name : $value"
            fi
        done
    fi
}

recovery_shell() {

    require_root

    warn "entering recovery shell"

    PS1="[timmy-recovery]# " bash --noprofile --norc
}

recovery_repair() {

    require_root

    header

    loading "checking filesystems"

    verbose_print "target disk: /dev/mmcblk0"

    fsck -fy /dev/mmcblk0p1 2>/dev/null

    cgpt show /dev/mmcblk0 | page_output

    if [ "$verbose_mode" -eq 1 ]; then

        verbose_print "block device information"

        lsblk -f | while read -r line; do
            verbose_print "$line"
        done
    fi

    ok "repair sequence completed"
}

recovery_network() {

    loading "bringing interfaces online"

    ip link set wlan0 up 2>/dev/null
    dhclient wlan0 2>/dev/null

    ip addr | page_output
}

recovery_rollback() {

    require_root

    latest=$(ls -t "$backup_dir"/*.bin 2>/dev/null | head -1)

    if [ -z "$latest" ]; then
        err "no firmware backups found"
        exit 1
    fi

    verbose_print "restoring firmware image $latest"

    flashrom -p internal -w "$latest"

    ok "rollback completed"
}

chromeos_status() {

    header

    if command -v crossystem >/dev/null 2>&1; then

        printf " developer mode : %s\n" "$(crossystem devsw_boot)"
        printf " active slot    : %s\n" "$(crossystem mainfw_act)"

    else

        err "crossystem unavailable"

    fi

    echo
}

chromeos_verify() {

    header

    if command -v crossystem >/dev/null 2>&1; then

        echo " developer mode : $(crossystem devsw_boot)"
        echo " active slot    : $(crossystem mainfw_act)"
        echo " firmware id    : $(crossystem fwid)"
        echo " recovery reason: $(crossystem recovery_reason)"
        echo " tpm initialized: $(crossystem tpm_init_done)"
        echo " wp switch      : $(crossystem wpsw_cur)"
        echo " rw legacy      : $(crossystem dev_boot_legacy)"

    else
        err "crossystem unavailable"
    fi
}

chromeos_partitions() {

    header

    cgpt show /dev/mmcblk0 | page_output

    echo

    lsblk | page_output
}

chromeos_firmware() {

    header

    printf " bios vendor : %s\n" "$(cat /sys/class/dmi/id/bios_vendor 2>/dev/null)"
    printf " bios version: %s\n" "$(cat /sys/class/dmi/id/bios_version 2>/dev/null)"
    printf " bios date   : %s\n" "$(cat /sys/class/dmi/id/bios_date 2>/dev/null)"
}

find_vm_image() {

    image="$1"

    if [ -f "$image" ]; then
        echo "$image"
        return
    fi

    case "$image" in

        alpine)
            remote_url="https://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/x86_64/alpine-virt-3.22.0-x86_64.iso"
            local_file="$image_dir/alpine.iso"
            required_mb=300
            ;;

        debian)
            remote_url="https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-13.0.0-amd64-netinst.iso"
            local_file="$image_dir/debian.iso"
            required_mb=1000
            ;;

        tinycore)
            remote_url="http://tinycorelinux.net/15.x/x86_64/release/TinyCorePure64.iso"
            local_file="$image_dir/tinycore.iso"
            required_mb=300
            ;;

        arch)
            remote_url="https://geo.mirror.pkgbuild.com/iso/latest/archlinux-x86_64.iso"
            local_file="$image_dir/arch.iso"
            required_mb=2500
            ;;

        fedora)
            remote_url="https://download.fedoraproject.org/pub/fedora/linux/releases/42/Workstation/x86_64/iso/Fedora-Workstation-Live-x86_64-42-1.1.iso"
            local_file="$image_dir/fedora.iso"
            required_mb=3500
            ;;

        *)
            err "unknown image"
            exit 1
            ;;

    esac

    if [ -f "$local_file" ]; then

        ok "cached image detected"

        verbose_print "using cached image: $local_file"

        echo "$local_file"
        return
    fi

    fetch_cleanup "$required_mb"

    warn "image missing locally"

    loading "downloading image"

    verbose_print "download url : $remote_url"
    verbose_print "cache path   : $local_file"

    start_time=$(date +%s)

    if command -v curl >/dev/null 2>&1; then

        curl \
            -L \
            --progress-bar \
            "$remote_url" \
            -o "$local_file"

    elif command -v wget >/dev/null 2>&1; then

        wget \
            --show-progress \
            "$remote_url" \
            -O "$local_file"

    else

        err "no downloader available"
        exit 1
    fi

    if [ ! -f "$local_file" ]; then
        err "download failed"
        exit 1
    fi

    end_time=$(date +%s)

    elapsed=$((end_time - start_time))

    downloaded_size=$(du -h "$local_file" | awk '{print $1}')

    ok "image installed"

    verbose_print "downloaded image size : $downloaded_size"
    verbose_print "download time         : ${elapsed}s"

    echo "$local_file"
}

vm_backend_detect() {

    if command -v crosvm >/dev/null 2>&1; then
        echo "crosvm"
        return
    fi

    if command -v kvm >/dev/null 2>&1; then
        echo "kvm"
        return
    fi

    if command -v qemu-system-x86_64 >/dev/null 2>&1; then
        echo "qemu"
        return
    fi

    echo "none"
}

vm_start() {

    require_root

    requested="$3"

    image=$(find_vm_image "$requested")
    backend=$(vm_backend_detect)

    header

    printf "${white}virtual machine manager${reset}\n\n"

    printf " backend : %s\n" "$backend"
    printf " image   : %s\n\n" "$image"

    if [ "$verbose_mode" -eq 1 ]; then

        verbose_print "vm backend selected: $backend"
        verbose_print "vm image path: $image"
        verbose_print "allocated memory: 2048mb"
        verbose_print "allocated cpus: 2"
    fi

    case "$backend" in

        crosvm)

            crosvm run \
                --mem 2048 \
                --cpus 2 \
                "$image"
            ;;

        kvm)

            kvm \
                -m 2048 \
                -cdrom "$image"
            ;;

        qemu)

            qemu-system-x86_64 \
                -m 2048 \
                -smp 2 \
                -enable-kvm \
                -cdrom "$image"
            ;;

        *)

            err "no vm backend detected"
            exit 1
            ;;
    esac
}
vm_list() {

    header

    printf "${white}installed vm images${reset}\n\n"

    ls -lh "$image_dir" | page_output

    echo
}

logs_cmd() {

    header

    tail -n 100 "$log_file" | page_output
}

logs_follow() {

    header

    tail -f "$log_file"
}

logs_errors() {

    header

    grep "\[fail\]" "$log_file" | page_output
}

history_cmd() {

    header

    tail -n 50 "$history_file" | page_output
}

unsafe_enable() {

    require_root

    echo "unsafe=enabled" > "$config_dir/unsafe.conf"

    ok "unsafe mode enabled"
}

unsafe_disable() {

    require_root

    rm -f "$config_dir/unsafe.conf"

    ok "unsafe mode disabled"
}

unsafe_status() {

    if [ -f "$config_dir/unsafe.conf" ]; then
        printf "${red}unsafe mode enabled${reset}\n"
    else
        printf "${green}unsafe mode disabled${reset}\n"
    fi
}

firmware_backup() {

    require_root

    backup_file="$backup_dir/firmware_$(date +%Y%m%d_%H%M%S).bin"

    flashrom -p internal -r "$backup_file"

    ok "firmware backup completed"

    echo "$backup_file"
}

help_cmd() {

    header

cat << EOF

flags

--verbose  enable verbose logging
--scroll   enable scrollable output

status
monitor
benchmark

hardware scan

network scan
network ping <host>
network trace <host>
network ports
network wifi scan
network speedtest
network sniff

thermal
battery health

chromeos status
chromeos verify
chromeos firmware
chromeos partitions

recovery shell
recovery repair
recovery network
recovery rollback

vm start alpine
vm start debian
vm start tinycore
vm start arch
vm start fedora

vm list

logs
logs follow
logs errors

history

unsafe enable
unsafe disable
unsafe status

firmware backup

help

EOF
}

case "$1" in

    --verbose|-v|--scroll|-s)
        shift
        ;;
esac

case "$1" in

    status)
        status_cmd
        ;;

    monitor)
        monitor_cmd
        ;;

    benchmark)
        benchmark_cmd
        ;;

    hardware)

        case "$2" in

            scan)
                hardware_scan
                ;;

            *)
                err "invalid hardware command"
                ;;

        esac
        ;;

    network)

        case "$2" in

            scan)
                network_scan
                ;;

            ping)
                network_ping "$@"
                ;;

            trace)
                network_trace "$@"
                ;;

            ports)
                network_ports
                ;;

            speedtest)
                network_speedtest
                ;;

            sniff)
                network_sniff
                ;;

            wifi)

                case "$3" in

                    scan)
                        network_wifi_scan
                        ;;

                    *)
                        err "invalid wifi command"
                        ;;

                esac
                ;;

            *)
                err "invalid network command"
                ;;

        esac
        ;;

    thermal)
        thermal_cmd
        ;;

    battery)

        case "$2" in

            health)
                battery_health
                ;;

            *)
                err "invalid battery command"
                ;;

        esac
        ;;

    recovery)

        case "$2" in

            shell)
                recovery_shell
                ;;

            repair)
                recovery_repair
                ;;

            network)
                recovery_network
                ;;

            rollback)
                recovery_rollback
                ;;

            *)
                err "invalid recovery command"
                ;;

        esac
        ;;

    chromeos)

        case "$2" in

            status)
                chromeos_status
                ;;

            verify)
                chromeos_verify
                ;;

            firmware)
                chromeos_firmware
                ;;

            partitions)
                chromeos_partitions
                ;;

            *)
                err "invalid chromeos command"
                ;;

        esac
        ;;

    vm)

        case "$2" in

            start)
                vm_start "$@"
                ;;

            list)
                vm_list
                ;;

            *)
                err "invalid vm command"
                ;;

        esac
        ;;

    logs)

        case "$2" in

            follow)
                logs_follow
                ;;

            errors)
                logs_errors
                ;;

            *)
                logs_cmd
                ;;

        esac
        ;;

    history)
        history_cmd
        ;;

    unsafe)

        case "$2" in

            enable)
                unsafe_enable
                ;;

            disable)
                unsafe_disable
                ;;

            status)
                unsafe_status
                ;;

            *)
                err "invalid unsafe command"
                ;;

        esac
        ;;

    firmware)

        case "$2" in

            backup)
                firmware_backup
                ;;

            *)
                err "invalid firmware command"
                ;;

        esac
        ;;

    help|"")
        help_cmd
        ;;

    *)
        err "unknown command"
        help_cmd
        ;;

esac