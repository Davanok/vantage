#!/usr/bin/env bash
# Requirement: rofi, xinput, nmcli (NetworkManager), pactl (Pulse/pipewire-pulse), sudo (for /proc/acpi/call)
# Lenovo Vantage for rofi — now with Power Mode control (ACPI)

ENABLE_FAN_MODE=1

# VPC folder (if there are several — take the first one)
VPC_DIR="$(printf "%s\n" /sys/bus/platform/devices/VPC2004:* | head -n1)"

# Touchpad id
touchpad_id="$(xinput --list 2>/dev/null | grep -i "Touchpad" | sed -n 's/.*id=\([0-9]*\).*/\1/p' | head -n1)"

# --- ACPI Power Mode constants (your values) ---
ACPI_BALANCE="\_SB.PCI0.LPC0.EC0.VPC0.DYTC 0x000FB001"
ACPI_POWER="\_SB.PCI0.LPC0.EC0.VPC0.DYTC 0x0012B001"
ACPI_ECO="\_SB.PCI0.LPC0.EC0.VPC0.DYTC 0x0013B001"
ACPI_MODE="\_SB.PCI0.LPC0.EC0.SPMO"

# Read current Power Mode (returns 0/1/2 or empty)
read_power_mode() {
    local out
    out="$(sudo sh -c "echo '$ACPI_MODE' > /proc/acpi/call; tr -d '\0' < /proc/acpi/call" 2>/dev/null || true)"
    # If the command returned something like "0x0" or "0x1"...
    if [[ -n "$out" ]]; then
        out="${out:2}"  # cut off the first 2 characters (0x)
        echo "$out"
    else
        echo ""
    fi
}

# Convert mode number to human-readable text (with icon)
get_power_mode_status() {
    local m
    m="$(read_power_mode)"
    case "$m" in
        0) echo "Balanced" ;;      #   Balanced
        1) echo "Performance" ;;   #   Performance
        2) echo "Battery" ;;       #   Battery
        *) echo "Unknown" ;;
    esac
}

# Set mode by number (0/1/2)
set_power_mode_by_id() {
    local id="$1"
    case "$id" in
        0)
            sudo sh -c "echo '$ACPI_BALANCE' > /proc/acpi/call"
            notify-send "Power Mode" "Balanced — Intelligent Cooling"
            ;;
        1)
            sudo sh -c "echo '$ACPI_POWER' > /proc/acpi/call"
            notify-send "Power Mode" "Performance — Extreme Performance"
            ;;
        2)
            sudo sh -c "echo '$ACPI_ECO' > /proc/acpi/call"
            notify-send "Power Mode" "Battery — Battery Saving"
            ;;
        *)
            notify-send "Power Mode" "Unknown mode: $id"
            ;;
    esac
}

# Set mode by name (alternative)
set_power_mode_by_name() {
    case "$(echo "$1" | tr '[:upper:]' '[:lower:]')" in
        balanced) set_power_mode_by_id 0 ;;
        performance) set_power_mode_by_id 1 ;;
        battery) set_power_mode_by_id 2 ;;
        next)
            local cur
            cur="$(read_power_mode)"
            # if empty — assume 0
            cur="${cur:-0}"
            local next=$(((cur + 1) % 3))
            set_power_mode_by_id "$next"
            ;;
        *) notify-send "Power Mode" "Unknown selection: $1" ;;
    esac
}

# --- other statuses (from previous script) ---
get_conservation_mode_status() {
    local f="$VPC_DIR/conservation_mode"
    [[ -f "$f" ]] || { echo "N/A"; return; }
    awk '{print ($1 == "1") ? "On" : "Off"}' "$f"
}

get_usb_charging_status() {
    local f="$VPC_DIR/usb_charging"
    [[ -f "$f" ]] || { echo "N/A"; return; }
    awk '{print ($1 == "1") ? "On" : "Off"}' "$f"
}

get_fan_mode_status() {
    local f="$VPC_DIR/fan_mode"
    [[ -f "$f" ]] || { echo "N/A"; return; }
    awk '{
        if ($1 == "133" || $1 == "0") print "Super Silent";
        else if ($1 == "1") print "Standard";
        else if ($1 == "2") print "Dust Cleaning";
        else if ($1 == "4") print "Efficient Thermal Dissipation";
        else print $1
    }' "$f"
}

get_fn_lock_status() {
    local f="$VPC_DIR/fn_lock"
    [[ -f "$f" ]] || { echo "N/A"; return; }
    awk '{print ($1 == "1") ? "Off" : "On"}' "$f"
}

get_camera_status() {
    lsmod | grep -q 'uvcvideo' && echo "On" || echo "Off"
}

get_microphone_status() {
    if command -v pactl >/dev/null 2>&1; then
        pactl get-source-mute @DEFAULT_SOURCE@ 2>/dev/null | awk '{print ($2 == "yes") ? "Muted" : "Active"}'
    else
        echo "N/A"
    fi
}

get_touchpad_status() {
    if [[ -n "$touchpad_id" ]]; then
        xinput --list-props "$touchpad_id" 2>/dev/null | grep -E "Device Enabled" | awk -F: '{print ($2+0 == 1) ? "On" : "Off"}'
    else
        echo "N/A"
    fi
}

get_wifi_status() {
    if command -v nmcli >/dev/null 2>&1; then
        nmcli radio wifi 2>/dev/null | awk '{print ($1 == "enabled") ? "On" : "Off"}'
    else
        echo "N/A"
    fi
}

# --- rofi helper without extra mesg line ---
rofi_menu() {
    local prompt="$1"
    shift
    printf "%s\n" "$@" | rofi -dmenu -i -p "$prompt"
}

# --- main menu loop ---
main() {
    command -v rofi >/dev/null 2>&1 || { echo "rofi is not installed"; exit 1; }

    while :; do
        options=()

        [[ -f "$VPC_DIR/conservation_mode" ]] && options+=("Conservation Mode — $(get_conservation_mode_status)")
        [[ -f "$VPC_DIR/usb_charging" ]] && options+=("Always-On USB — $(get_usb_charging_status)")
        [[ -f "$VPC_DIR/fan_mode" && $ENABLE_FAN_MODE -eq 1 ]] && options+=("Fan Mode — $(get_fan_mode_status)")
        [[ -f "$VPC_DIR/fn_lock" ]] && options+=("FN Lock — $(get_fn_lock_status)")
        modinfo -n uvcvideo >/dev/null 2>&1 && options+=("Camera — $(get_camera_status)")
        command -v pactl >/dev/null 2>&1 && options+=("Microphone — $(get_microphone_status)")
        [[ -n "$touchpad_id" ]] && options+=("Touchpad — $(get_touchpad_status)")
        command -v nmcli >/dev/null 2>&1 && options+=("WiFi — $(get_wifi_status)")

        # Add Power Mode to the menu (always, if /proc/acpi/call is available)
        if [[ -w /proc/acpi/call || -e /proc/acpi/call ]]; then
            options+=("Power Mode — $(get_power_mode_status)")
        fi

        [[ ${#options[@]} -eq 0 ]] && { rofi -e "No controls found"; exit 0; }

        menu="$(printf "%s\n" "${options[@]}" | rofi -dmenu -i -p "Lenovo Vantage — select action")" || break

        case "$menu" in
            "Conservation Mode"* )
                status="$(get_conservation_mode_status)"
                choice="$(rofi_menu "Conservation Mode" "Activate" "Deactivate")" || continue
                if [[ "$choice" == "Activate" ]]; then
                    echo "1" | pkexec tee "$VPC_DIR/conservation_mode" >/dev/null
                elif [[ "$choice" == "Deactivate" ]]; then
                    echo "0" | pkexec tee "$VPC_DIR/conservation_mode" >/dev/null
                fi
                ;;
            "Always-On USB"* )
                status="$(get_usb_charging_status)"
                choice="$(rofi_menu "Always-On USB" "Activate" "Deactivate")" || continue
                if [[ "$choice" == "Activate" ]]; then
                    echo "1" | pkexec tee "$VPC_DIR/usb_charging" >/dev/null
                elif [[ "$choice" == "Deactivate" ]]; then
                    echo "0" | pkexec tee "$VPC_DIR/usb_charging" >/dev/null
                fi
                ;;
            "Fan Mode"* )
                status="$(get_fan_mode_status)"
                choice="$(rofi_menu "Fan Mode" "Super Silent" "Standard" "Dust Cleaning" "Efficient Thermal Dissipation")" || continue
                case "$choice" in
                    "Super Silent") echo "0" | pkexec tee "$VPC_DIR/fan_mode" >/dev/null ;;
                    "Standard") echo "1" | pkexec tee "$VPC_DIR/fan_mode" >/dev/null ;;
                    "Dust Cleaning") echo "2" | pkexec tee "$VPC_DIR/fan_mode" >/dev/null ;;
                    "Efficient Thermal Dissipation") echo "4" | pkexec tee "$VPC_DIR/fan_mode" >/dev/null ;;
                esac
                ;;
            "FN Lock"* )
                status="$(get_fn_lock_status)"
                choice="$(rofi_menu "FN Lock" "Activate" "Deactivate")" || continue
                if [[ "$choice" == "Activate" ]]; then
                    echo "0" | pkexec tee "$VPC_DIR/fn_lock" >/dev/null
                elif [[ "$choice" == "Deactivate" ]]; then
                    echo "1" | pkexec tee "$VPC_DIR/fn_lock" >/dev/null
                fi
                ;;
            "Camera"* )
                status="$(get_camera_status)"
                choice="$(rofi_menu "Camera" "Activate" "Deactivate")" || continue
                if [[ "$choice" == "Activate" ]]; then
                    pkexec modprobe uvcvideo
                elif [[ "$choice" == "Deactivate" ]]; then
                    pkexec modprobe -r uvcvideo
                fi
                ;;
            "Microphone"* )
                status="$(get_microphone_status)"
                choice="$(rofi_menu "Microphone" "Mute" "Unmute")" || continue
                if [[ "$choice" == "Mute" ]]; then
                    pactl set-source-mute @DEFAULT_SOURCE@ 1
                elif [[ "$choice" == "Unmute" ]]; then
                    pactl set-source-mute @DEFAULT_SOURCE@ 0
                fi
                ;;
            "Touchpad"* )
                status="$(get_touchpad_status)"
                choice="$(rofi_menu "Touchpad" "Activate" "Deactivate")" || continue
                if [[ -n "$touchpad_id" ]]; then
                    if [[ "$choice" == "Activate" ]]; then
                        xinput enable "$touchpad_id"
                    elif [[ "$choice" == "Deactivate" ]]; then
                        xinput disable "$touchpad_id"
                    fi
                else
                    rofi -e "Touchpad not found"
                fi
                ;;
            "WiFi"* )
                status="$(get_wifi_status)"
                choice="$(rofi_menu "WiFi" "Activate" "Deactivate")" || continue
                if [[ "$choice" == "Activate" ]]; then
                    nmcli radio wifi on
                elif [[ "$choice" == "Deactivate" ]]; then
                    nmcli radio wifi off
                fi
                ;;
            "Power Mode"* )
                pm_choice="$(rofi_menu "Power Mode (current: $(get_power_mode_status))" "Balanced" "Performance" "Battery")" || continue
                case "$pm_choice" in
                    "Balanced") set_power_mode_by_name balanced ;;
                    "Performance") set_power_mode_by_name performance ;;
                    "Battery") set_power_mode_by_name battery ;;
                esac
                ;;
            *)
                break
                ;;
        esac

        sleep 0.1
    done
}

main "$@"
