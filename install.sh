#! /usr/bin/env bash

# Exit Immediately if a command fails
set -o errexit

readonly ROOT_UID=0
readonly Project_Name="Frosts Installer"
readonly MAX_DELAY=20                               # max delay for user to enter root password
tui_root_login=

THEME_DIR="/usr/share/grub/themes"
REO_DIR="$(cd "$(dirname "$0")" && pwd)"

# Name the theme is installed under: defaults to the folder name the
# installer lives in, so this script can be dropped into ANY theme folder.
THEME_NAME="$(basename "${REO_DIR}" | tr ' ' '-' | tr -cd 'A-Za-z0-9._-')"
[[ -z "${THEME_NAME}" ]] && THEME_NAME="grub-theme"

install_boot='false'
do_remove='false'
skip_menu='false'

#################################
# :::::: C O L O R S ::::::
#################################

CDEF=" \033[0m"                                     # default color
b_CGSC=" \033[1;32m"                                # bold success color
b_CRER=" \033[1;31m"                                # bold error color
b_CWAR=" \033[1;33m"                                # bold warning color
b_CCIN=" \033[1;36m"                                # bold info color
b_CMEN=" \033[1;35m"                                # bold menu color

#######################################
# :::::: F U N C T I O N S ::::::
#######################################

prompt () {
    case ${1} in
        "-s"|"--success") echo -e "${b_CGSC}${2}${CDEF}" ;;
        "-e"|"--error") echo -e "${b_CRER}${2}${CDEF}" ;;
        "-w"|"--warning") echo -e "${b_CWAR}${2}${CDEF}" ;;
        "-i"|"--info") echo -e "${b_CCIN}${2}${CDEF}" ;;
        "-m"|"--menu") echo -e "${b_CMEN}${2}${CDEF}" ;;
        *) echo -e "${2}" ;;
    esac
}

function has_command() {
    command -v "$1" &> /dev/null
}

usage() {
    cat << EOF
Usage: $0 [OPTION]...

OPTIONS:
    -b, --boot        install theme into '/boot/grub' or '/boot/grub2' instead of /usr/share/grub/themes
    -g, --generate    do not install, just copy theme files into DIR   (e.g. -g /some/dir)
    -r, --remove      remove the theme and reset GRUB_THEME
    -m, --menu        launch interactive GRUB customization menu
    -h, --help        show this help

EOF
}

install_program () {
    if has_command zypper; then
        zypper in -y "$@"
    elif has_command swupd; then
        swupd bundle-add "$@"
    elif has_command apt-get; then
        apt-get install -y "$@"
    elif has_command dnf; then
        dnf install -y "$@"
    elif has_command yum; then
        yum install -y "$@"
    elif has_command pacman; then
        pacman -Syyu --noconfirm --needed "$@"
    elif has_command xbps-install; then
        xbps-install -Sy "$@"
    elif has_command eopkg; then
        eopkg -y install "$@"
    fi
}

install_depends() {
    local depend=${1}
    if [[ ! "$(command -v "${depend}" 2> /dev/null)" ]]; then
        prompt -w "\n '${depend}' needs to be installed for this script"
        install_program "${depend}"
    fi
}

# Copy every file in the theme folder into the target directory, skipping
# the installer itself and any repo/doc cruft. This makes the script work
# for ANY theme, regardless of its specific asset filenames.
generate() {
    local target_dir="${1}"

    prompt -i "\n Checking for the existence of themes directory..."
    [[ -d "${target_dir}" ]] && rm -rf "${target_dir}"
    mkdir -p "${target_dir}"

    prompt -i "\n Installing ${THEME_NAME} theme..."

    if [[ ! -f "${REO_DIR}/theme.txt" ]]; then
        prompt -e "\n [ Error! ] -> No 'theme.txt' found in ${REO_DIR}."
        prompt -e " Make sure install.sh sits inside the theme folder itself."
        exit 1
    fi

    shopt -s dotglob nullglob
    for item in "${REO_DIR}"/*; do
        local base
        base="$(basename "${item}")"
        case "${base}" in
            install.sh|README|readme*|LICENSE*|*.md|.git|.gitignore)
                continue
                ;;
        esac
        cp -a --no-preserve=ownership "${item}" "${target_dir}/"
    done
    shopt -u dotglob nullglob
}

updating_grub() {
    if has_command update-grub; then
        update-grub
    elif has_command grub-mkconfig; then
        grub-mkconfig -o /boot/grub/grub.cfg
    elif has_command zypper || has_command transactional-update; then
        grub2-mkconfig -o /boot/grub2/grub.cfg
    elif has_command dnf || has_command rpm-ostree; then
        if [[ -f /boot/grub2/grub.cfg ]]; then
            prompt -s "Found config file at /boot/grub2/grub.cfg ...\n"
            grub2-mkconfig -o /boot/grub2/grub.cfg
        elif [[ -f /boot/efi/EFI/fedora/grub.cfg ]]; then
            prompt -s "Found config file at /boot/efi/EFI/fedora/grub.cfg ...\n"
            grub2-mkconfig -o /boot/efi/EFI/fedora/grub.cfg
        fi
    fi

    prompt -s "\n * All done!"
}

# Function to get current GRUB settings
get_grub_setting() {
    local setting="${1}"
    local default="${2}"
    local value=""
    
    # Check /etc/default/grub first
    if [[ -f "/etc/default/grub" ]]; then
        value=$(grep "^${setting}=" /etc/default/grub | cut -d'"' -f2 | head -n1)
        [[ -z "${value}" ]] && value=$(grep "^${setting}=" /etc/default/grub | cut -d'=' -f2 | head -n1)
    fi
    
    # If not found, use default
    [[ -z "${value}" ]] && value="${default}"
    
    echo "${value}"
}

# Function to set GRUB setting
set_grub_setting() {
    local setting="${1}"
    local value="${2}"
    local config_file="${3:-/etc/default/grub}"
    
    if [[ ! -f "${config_file}" ]]; then
        return 1
    fi
    
    # Backup the file if it hasn't been backed up yet
    if [[ ! -f "${config_file}.bak" ]]; then
        cp -an "${config_file}" "${config_file}.bak"
    fi
    
    # Remove any existing setting
    sed -i "/^${setting}=/d" "${config_file}"
    
    # Add the new setting
    echo "${setting}=\"${value}\"" >> "${config_file}"
}

# Interactive menu for GRUB customization
grub_customization_menu() {
    clear
    prompt -m "═══════════════════════════════════════════════════════════════"
    prompt -m "           GRUB CUSTOMIZATION MENU"
    prompt -m "═══════════════════════════════════════════════════════════════"
    echo ""
    
    # Get current settings
    local current_timeout=$(get_grub_setting "GRUB_TIMEOUT" "10")
    local current_default=$(get_grub_setting "GRUB_DEFAULT" "0")
    local current_saved=$(grep "^GRUB_SAVEDEFAULT=" /etc/default/grub >/dev/null 2>&1 && echo "true" || echo "false")
    
    prompt -i "Current Settings:"
    echo "  • GRUB_TIMEOUT: ${current_timeout} seconds"
    echo "  • GRUB_DEFAULT: ${current_default}"
    echo "  • SAVE DEFAULT: ${current_saved}"
    echo ""
    
    prompt -m "Select an option:"
    echo "  1) Change timeout (GRUB_TIMEOUT)"
    echo "  2) Change default boot entry (GRUB_DEFAULT)"
    echo "  3) Toggle 'Save Default Entry' (GRUB_SAVEDEFAULT)"
    echo "  4) Set timeout style (hidden/show menu)"
    echo "  5) Advanced: Boot order / Menu entry management"
    echo "  6) Reset to default GRUB settings"
    echo "  7) Show boot entries"
    echo "  8) Apply settings and exit"
    echo "  9) Exit without saving"
    echo ""
    
    read -r -p "  Enter your choice [1-9]: " choice
    
    case "${choice}" in
        1) change_timeout ;;
        2) change_default_entry ;;
        3) toggle_save_default ;;
        4) set_timeout_style ;;
        5) boot_order_menu ;;
        6) reset_grub_settings ;;
        7) show_boot_entries ;;
        8) apply_settings ;;
        9) exit 0 ;;
        *) prompt -e "Invalid option"; sleep 2; grub_customization_menu ;;
    esac
}

change_timeout() {
    clear
    prompt -m "═══════════════════════════════════════════════════════════════"
    prompt -m "           CHANGE BOOT TIMEOUT"
    prompt -m "═══════════════════════════════════════════════════════════════"
    echo ""
    
    local current_timeout=$(get_grub_setting "GRUB_TIMEOUT" "10")
    prompt -i "Current timeout: ${current_timeout} seconds"
    echo ""
    echo "  -1 = Wait forever (no timeout)"
    echo "   0 = Don't wait (boot immediately)"
    echo "   5-60 = Typical values (seconds)"
    echo ""
    
    read -r -p "  Enter new timeout value: " new_timeout
    
    if [[ "${new_timeout}" =~ ^-?[0-9]+$ ]]; then
        set_grub_setting "GRUB_TIMEOUT" "${new_timeout}"
        prompt -s "✓ Timeout set to ${new_timeout} seconds"
    else
        prompt -e "✗ Invalid value. Please enter a number."
    fi
    
    echo ""
    read -r -p "  Press Enter to continue..."
    grub_customization_menu
}

change_default_entry() {
    clear
    prompt -m "═══════════════════════════════════════════════════════════════"
    prompt -m "           CHANGE DEFAULT BOOT ENTRY"
    prompt -m "═══════════════════════════════════════════════════════════════"
    echo ""
    
    echo "  Current default: $(get_grub_setting "GRUB_DEFAULT" "0")"
    echo ""
    echo "  Options:"
    echo "    0, 1, 2... = Menu entry index (starting from 0)"
    echo "    saved      = Use the last booted entry"
    echo "    >GRUB_ENTRY_NAME< = Exact menu entry name (case sensitive)"
    echo ""
    
    read -r -p "  Enter default entry: " new_default
    
    if [[ -n "${new_default}" ]]; then
        set_grub_setting "GRUB_DEFAULT" "${new_default}"
        prompt -s "✓ Default entry set to: ${new_default}"
    else
        prompt -e "✗ No value provided"
    fi
    
    echo ""
    read -r -p "  Press Enter to continue..."
    grub_customization_menu
}

toggle_save_default() {
    clear
    prompt -m "═══════════════════════════════════════════════════════════════"
    prompt -m "           TOGGLE SAVE DEFAULT ENTRY"
    prompt -m "═══════════════════════════════════════════════════════════════"
    echo ""
    
    if grep -q "^GRUB_SAVEDEFAULT=" /etc/default/grub 2>/dev/null; then
        sed -i '/^GRUB_SAVEDEFAULT=/d' /etc/default/grub
        prompt -s "✓ GRUB_SAVEDEFAULT disabled"
    else
        echo "GRUB_SAVEDEFAULT=true" >> /etc/default/grub
        prompt -s "✓ GRUB_SAVEDEFAULT enabled - GRUB will remember the last booted entry"
    fi
    
    echo ""
    read -r -p "  Press Enter to continue..."
    grub_customization_menu
}

set_timeout_style() {
    clear
    prompt -m "═══════════════════════════════════════════════════════════════"
    prompt -m "           SET TIMEOUT STYLE"
    prompt -m "═══════════════════════════════════════════════════════════════"
    echo ""
    
    echo "  Current timeout: $(get_grub_setting "GRUB_TIMEOUT" "10")"
    echo "  Current timeout style:"
    
    if grep -q "^GRUB_TIMEOUT_STYLE=" /etc/default/grub 2>/dev/null; then
        local style=$(get_grub_setting "GRUB_TIMEOUT_STYLE" "menu")
        echo "  Style: ${style}"
    else
        echo "  Style: menu (default)"
    fi
    echo ""
    echo "  1) Show menu (GRUB_TIMEOUT_STYLE=menu)"
    echo "  2) Hidden menu (GRUB_TIMEOUT_STYLE=hidden)"
    echo "  3) Countdown (GRUB_HIDDEN_TIMEOUT)"
    echo ""
    
    read -r -p "  Enter choice [1-3]: " style_choice
    
    case "${style_choice}" in
        1)
            sed -i '/^GRUB_TIMEOUT_STYLE=/d' /etc/default/grub
            sed -i '/^GRUB_HIDDEN_TIMEOUT=/d' /etc/default/grub
            prompt -s "✓ Menu will be shown"
            ;;
        2)
            echo "GRUB_TIMEOUT_STYLE=hidden" >> /etc/default/grub
            sed -i '/^GRUB_HIDDEN_TIMEOUT=/d' /etc/default/grub
            prompt -s "✓ Menu will be hidden"
            ;;
        3)
            sed -i '/^GRUB_TIMEOUT_STYLE=/d' /etc/default/grub
            echo "GRUB_HIDDEN_TIMEOUT=${current_timeout}" >> /etc/default/grub
            prompt -s "✓ Countdown will be shown"
            ;;
        *)
            prompt -e "✗ Invalid option"
            ;;
    esac
    
    echo ""
    read -r -p "  Press Enter to continue..."
    grub_customization_menu
}

boot_order_menu() {
    clear
    prompt -m "═══════════════════════════════════════════════════════════════"
    prompt -m "           BOOT ORDER MANAGEMENT"
    prompt -m "═══════════════════════════════════════════════════════════════"
    echo ""
    
    prompt -i "Current boot order (from GRUB config):"
    echo ""
    
    # Show available boot entries from grub.cfg
    if [[ -f "/boot/grub/grub.cfg" ]]; then
        grep -E "^menuentry|^submenu" /boot/grub/grub.cfg | head -20 | nl -w2 -s') ' | sed 's/^/  /'
        echo ""
        prompt -w "Note: Only showing first 20 entries"
        echo ""
    else
        prompt -e "Could not find grub.cfg"
        echo ""
    fi
    
    echo "  What would you like to do?"
    echo "  1) Set default entry by index (e.g., 0 for first entry)"
    echo "  2) Set default by exact name"
    echo "  3) Set to 'saved' (last booted)"
    echo "  4) Show all boot entries in detail"
    echo "  5) Back to main menu"
    echo ""
    
    read -r -p "  Enter choice [1-5]: " order_choice
    
    case "${order_choice}" in
        1)
            read -r -p "  Enter entry index (starting from 0): " idx
            if [[ "${idx}" =~ ^[0-9]+$ ]]; then
                set_grub_setting "GRUB_DEFAULT" "${idx}"
                prompt -s "✓ Default set to entry index: ${idx}"
            else
                prompt -e "✗ Invalid index"
            fi
            ;;
        2)
            read -r -p "  Enter exact menu entry name: " name
            if [[ -n "${name}" ]]; then
                set_grub_setting "GRUB_DEFAULT" "${name}"
                prompt -s "✓ Default set to: ${name}"
            else
                prompt -e "✗ No name provided"
            fi
            ;;
        3)
            set_grub_setting "GRUB_DEFAULT" "saved"
            echo "GRUB_SAVEDEFAULT=true" >> /etc/default/grub
            prompt -s "✓ Default set to 'saved' (last booted entry)"
            ;;
        4)
            echo ""
            prompt -i "All boot entries:"
            echo ""
            if [[ -f "/boot/grub/grub.cfg" ]]; then
                grep -E "^menuentry|^submenu" /boot/grub/grub.cfg | sed 's/^/  /' | sed 's/--class /\\n    /'
            fi
            echo ""
            ;;
        5)
            grub_customization_menu
            return
            ;;
        *)
            prompt -e "✗ Invalid option"
            ;;
    esac
    
    echo ""
    read -r -p "  Press Enter to continue..."
    boot_order_menu
}

show_boot_entries() {
    clear
    prompt -m "═══════════════════════════════════════════════════════════════"
    prompt -m "           ALL BOOT ENTRIES"
    prompt -m "═══════════════════════════════════════════════════════════════"
    echo ""
    
    if [[ -f "/boot/grub/grub.cfg" ]]; then
        grep -E "^menuentry|^submenu" /boot/grub/grub.cfg | nl -w3 -s') ' | sed 's/^/  /'
    else
        prompt -e "Could not find /boot/grub/grub.cfg"
    fi
    
    echo ""
    read -r -p "  Press Enter to continue..."
    grub_customization_menu
}

reset_grub_settings() {
    clear
    prompt -m "═══════════════════════════════════════════════════════════════"
    prompt -m "           RESET GRUB SETTINGS"
    prompt -m "═══════════════════════════════════════════════════════════════"
    echo ""
    
    prompt -e "⚠ WARNING: This will reset all GRUB customizations!"
    read -r -p "  Are you sure? [y/N]: " confirm
    
    if [[ "${confirm}" =~ ^[Yy]$ ]]; then
        if [[ -f "/etc/default/grub.bak" ]]; then
            cp -f "/etc/default/grub.bak" "/etc/default/grub"
            prompt -s "✓ GRUB settings reset to original"
        else
            prompt -e "✗ No backup file found. Cannot reset."
        fi
    else
        prompt -i "Reset cancelled"
    fi
    
    echo ""
    read -r -p "  Press Enter to continue..."
    grub_customization_menu
}

apply_settings() {
    clear
    prompt -m "═══════════════════════════════════════════════════════════════"
    prompt -m "           APPLYING SETTINGS"
    prompt -m "═══════════════════════════════════════════════════════════════"
    echo ""
    
    prompt -i "Updating GRUB configuration..."
    echo ""
    
    if updating_grub; then
        prompt -s "✓ Settings applied successfully!"
        echo ""
        prompt -s "  Settings summary:"
        echo "    • Timeout: $(get_grub_setting "GRUB_TIMEOUT" "10") seconds"
        echo "    • Default: $(get_grub_setting "GRUB_DEFAULT" "0")"
        
        if grep -q "^GRUB_SAVEDEFAULT=" /etc/default/grub 2>/dev/null; then
            echo "    • Save default: Enabled"
        else
            echo "    • Save default: Disabled"
        fi
        
        if grep -q "^GRUB_TIMEOUT_STYLE=" /etc/default/grub 2>/dev/null; then
            echo "    • Timeout style: $(get_grub_setting "GRUB_TIMEOUT_STYLE" "menu")"
        fi
    else
        prompt -e "✗ Failed to update GRUB configuration"
    fi
    
    echo ""
    read -r -p "  Press Enter to continue..."
    grub_customization_menu
}

install() {
    if [[ "${UID}" -eq "${ROOT_UID}" ]]; then

        if [[ "${install_boot}" == 'true' ]]; then
            if [[ -d "/boot/grub" ]]; then
                THEME_DIR='/boot/grub/themes'
            fi
            if [[ -d "/boot/grub2" ]]; then
                THEME_DIR='/boot/grub2/themes'
            fi
        fi

        generate "${THEME_DIR}/${THEME_NAME}"

        prompt -i "\n Setting ${THEME_NAME} as default..."

        if [[ -f /etc/default/grub.bak ]]; then
            prompt -w "\n File '/etc/default/grub.bak' already exists!"
        else
            cp -an /etc/default/grub /etc/default/grub.bak
        fi

        # Fedora workaround for missing unicode.pf2
        if has_command dnf; then
            if [[ -f "/boot/grub2/fonts/unicode.pf2" ]]; then
                if grep -q "GRUB_FONT=" /etc/default/grub 2>/dev/null; then
                    sed -i "s|.*GRUB_FONT=.*|GRUB_FONT=/boot/grub2/fonts/unicode.pf2|" /etc/default/grub
                else
                    echo "GRUB_FONT=/boot/grub2/fonts/unicode.pf2" >> /etc/default/grub
                fi
            elif [[ -f "/boot/efi/EFI/fedora/fonts/unicode.pf2" ]]; then
                if grep -q "GRUB_FONT=" /etc/default/grub 2>/dev/null; then
                    sed -i "s|.*GRUB_FONT=.*|GRUB_FONT=/boot/efi/EFI/fedora/fonts/unicode.pf2|" /etc/default/grub
                else
                    echo "GRUB_FONT=/boot/efi/EFI/fedora/fonts/unicode.pf2" >> /etc/default/grub
                fi
            fi
        fi

        if grep -q "GRUB_THEME=" /etc/default/grub 2>/dev/null; then
            sed -i "s|.*GRUB_THEME=.*|GRUB_THEME=\"${THEME_DIR}/${THEME_NAME}/theme.txt\"|" /etc/default/grub
        else
            echo "GRUB_THEME=\"${THEME_DIR}/${THEME_NAME}/theme.txt\"" >> /etc/default/grub
        fi

        if grep -q "GRUB_BACKGROUND=" /etc/default/grub 2>/dev/null; then
            sed -i "s|.*GRUB_BACKGROUND=.*||" /etc/default/grub
        fi

        if grep -q "GRUB_TERMINAL=console" /etc/default/grub 2>/dev/null || grep -q "GRUB_TERMINAL=\"console\"" /etc/default/grub 2>/dev/null; then
            sed -i "s|.*GRUB_TERMINAL=.*|#GRUB_TERMINAL=console|" /etc/default/grub
        fi

        if grep -q "GRUB_TERMINAL_OUTPUT=console" /etc/default/grub 2>/dev/null || grep -q "GRUB_TERMINAL_OUTPUT=\"console\"" /etc/default/grub 2>/dev/null; then
            sed -i "s|.*GRUB_TERMINAL_OUTPUT=.*|#GRUB_TERMINAL_OUTPUT=console|" /etc/default/grub
        fi

        # Kali linux support: kali-themes.cfg is sourced AFTER /etc/default/grub
        # and silently overrides GRUB_THEME there, so it must be patched too.
        if [[ -f "/etc/default/grub.d/kali-themes.cfg" ]]; then
            if [[ ! -f "/etc/default/grub.d/kali-themes.cfg.bak" ]]; then
                cp -an /etc/default/grub.d/kali-themes.cfg /etc/default/grub.d/kali-themes.cfg.bak
            fi

            if grep -q "GRUB_THEME=" /etc/default/grub.d/kali-themes.cfg 2>/dev/null; then
                sed -i "s|.*GRUB_THEME=.*|GRUB_THEME=\"${THEME_DIR}/${THEME_NAME}/theme.txt\"|" /etc/default/grub.d/kali-themes.cfg
            else
                echo "GRUB_THEME=\"${THEME_DIR}/${THEME_NAME}/theme.txt\"" >> /etc/default/grub.d/kali-themes.cfg
            fi
        fi

        prompt -i "\n Updating grub config... \n"
        updating_grub
        prompt -w "\n * At the next restart of your computer you will see your new Grub theme: '${THEME_NAME}' \n"

    elif sudo -n true 2> /dev/null && echo; then
        if [[ "${install_boot}" == 'true' ]]; then
            sudo "$0" -b
        else
            sudo "$0"
        fi
    else
        if [[ -n ${tui_root_login} ]]; then
            if [[ "${install_boot}" == 'true' ]]; then
                sudo -S "$0" -b <<< "${tui_root_login}"
            else
                sudo -S "$0" <<< "${tui_root_login}"
            fi
        else
            prompt -e "\n [ Error! ] -> Run me as root! "
            read -r -p " [ Trusted ] Specify the root password : " -t ${MAX_DELAY} -s
            echo
            if sudo -S echo <<< "$REPLY" 2> /dev/null && echo; then
                if [[ "${install_boot}" == 'true' ]]; then
                    sudo "$0" -b <<< "${REPLY}"
                else
                    sudo "$0" <<< "${REPLY}"
                fi
            else
                sleep 3
                prompt -e "\n [ Error! ] -> Incorrect password!\n"
                exit 1
            fi
        fi
    fi
}

remove() {
    if [[ "${UID}" -eq "${ROOT_UID}" ]]; then
        prompt -i "Checking for the existence of themes directory..."

        local removed='false'
        for d in "/usr/share/grub/themes/${THEME_NAME}" "/boot/grub/themes/${THEME_NAME}" "/boot/grub2/themes/${THEME_NAME}"; do
            if [[ -d "${d}" ]]; then
                prompt -i "\n Found installed theme: '${d}'..."
                rm -rf "${d}"
                prompt -w "\n Removed: '${d}'..."
                removed='true'
            fi
        done

        if [[ "${removed}" == 'false' ]]; then
            prompt -e "\n ${THEME_NAME} theme does not appear to be installed!"
            exit 0
        fi

        local reset_any='false'
        for grub_config_location in "/etc/default/grub" "/etc/default/grub.d/kali-themes.cfg"; do
            [[ -f "${grub_config_location}" ]] || continue

            local current_theme=""
            current_theme="$(grep 'GRUB_THEME=' "${grub_config_location}" | grep -v '#' || true)"

            if [[ -n "${current_theme}" ]]; then
                sed --in-place='.bak' "s|${current_theme}|#GRUB_THEME=|" "${grub_config_location}"
                [[ -f "${grub_config_location}".back ]] && rm -f "${grub_config_location}".back
                reset_any='true'
            fi
        done

        if [[ "${reset_any}" == 'true' ]]; then
            prompt -i "\n Resetting grub theme...\n"
            updating_grub
        else
            prompt -e "\n No active theme found in /etc/default/grub or kali-themes.cfg."
            exit 1
        fi

    elif sudo -n true 2> /dev/null && echo; then
        sudo "$0" -r
    else
        prompt -e "\n [ Error! ] -> Run me as root! "
        read -r -p " [ Trusted ] Specify the root password : " -t ${MAX_DELAY} -s
        echo
        if sudo -S echo <<< "$REPLY" 2> /dev/null && echo; then
            sudo -S "$0" -r <<< "$REPLY"
        else
            sleep 3
            prompt -e "\n [ Error! ] -> Incorrect password!\n"
            exit 1
        fi
    fi
}

#######################################################
# :::::: A R G U M E N T   H A N D L I N G ::::::
#######################################################

generate_dir=""
launch_menu='false'

while [[ $# -gt 0 ]]; do
    case "${1}" in
        -r|--remove)
            do_remove='true'
            shift
            ;;
        -b|--boot)
            install_boot='true'
            shift
            ;;
        -g|--generate)
            shift
            generate_dir="${1}"
            shift
            ;;
        -m|--menu)
            launch_menu='true'
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            prompt -e "ERROR: Unrecognized option '$1'."
            prompt -i "Try '$0 --help' for more information."
            exit 1
            ;;
    esac
done

# Main execution
if [[ "${launch_menu}" == 'true' ]]; then
    # Check if running as root for menu
    if [[ "${UID}" -ne "${ROOT_UID}" ]]; then
        if sudo -n true 2> /dev/null; then
            sudo "$0" -m
            exit 0
        else
            prompt -e "\n [ Error! ] -> GRUB customization requires root privileges!"
            prompt -i "Please run with sudo: sudo $0 -m"
            exit 1
        fi
    fi
    grub_customization_menu
    exit 0
fi

if [[ "${do_remove}" == 'true' ]]; then
    remove
    exit 0
fi

if [[ -n "${generate_dir}" ]]; then
    generate "${generate_dir}"
    prompt -s "✓ Theme generated at: ${generate_dir}"
    exit 0
fi

# Default: install theme
install
