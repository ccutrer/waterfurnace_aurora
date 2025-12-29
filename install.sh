#!/bin/bash
#
# WaterFurnace Aurora Installation Script
# Interactive installer for the WaterFurnace Aurora gem
# Supports Debian/Ubuntu-based systems with focus on Raspberry Pi
#

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script configuration
REQUIRED_RUBY_MIN="2.5"
REQUIRED_RUBY_MAX="2.7"

# System packages to install
#SYSTEM_PACKAGES=("ruby" "ruby-dev" "build-essential")
SYSTEM_PACKAGES=("ruby" "ruby-dev")

# Gems to install
#GEMS_TO_INSTALL=("rake" "waterfurnace_aurora")
GEMS_TO_INSTALL=("waterfurnace_aurora")

# MQTT broker packages (optional)
MQTT_PACKAGES=("mosquitto" "mosquitto-clients")

# Print functions
print_header() {
    echo -e "\n${BLUE}===================================================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}===================================================================${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓ ${NC} $1"
}

print_error() {
    echo -e "${RED}✗ ${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠ ${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ ${NC} $1"
}

# Ask yes/no question
ask_yes_no() {
    local prompt="$1"
    local default="${2:-n}"

    if [ "$default" = "y" ]; then
        prompt="$prompt [Y/n]: "
    else
        prompt="$prompt [y/N]: "
    fi

    while true; do
        read -p "$prompt" response
        response=${response:-$default}
        case "$response" in
            [Yy]* ) return 0;;
            [Nn]* ) return 1;;
            * ) echo "Please answer yes or no.";;
        esac
    done
}

# Detect platform
detect_platform() {
    print_header "Detecting Platform"

    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        OS_VERSION=$VERSION_ID
        OS_NAME=$PRETTY_NAME
    else
        print_error "Cannot detect operating system"
        exit 1
    fi

    # Check if running on Raspberry Pi
    if [ -f /proc/device-tree/model ]; then
        PI_MODEL=$(tr -d '\0' < /proc/device-tree/model)
        if [[ $PI_MODEL == *"Raspberry Pi"* ]]; then
            IS_RASPBERRY_PI=true
            print_success "Detected Raspberry Pi: $PI_MODEL"
        else
            IS_RASPBERRY_PI=false
        fi
    else
        IS_RASPBERRY_PI=false
    fi

    print_info "Operating System: $OS_NAME"

    # Check if Debian-based
    if [[ "$OS" == "debian" ]] || [[ "$OS" == "ubuntu" ]] || [[ "$OS" == "raspbian" ]]; then
        PACKAGE_MANAGER="apt"
        print_success "Supported distribution detected"
    else
        print_warning "This script is optimized for Debian/Ubuntu-based systems"
        if ask_yes_no "Continue anyway?"; then
            PACKAGE_MANAGER="unknown"
        else
            exit 1
        fi
    fi
}

# Check if running as root for installation
check_privileges() {
    if [ "$EUID" -ne 0 ] && [ "$PACKAGE_MANAGER" = "apt" ]; then
        print_warning "This script requires sudo privileges for installing system packages"
        if ! sudo -v; then
            print_error "Failed to obtain sudo privileges"
            exit 1
        fi
        SUDO="sudo"
    else
        SUDO=""
    fi
}

# Install system dependencies
install_dependencies() {
    print_header "Installing System Dependencies"

    if [ "$PACKAGE_MANAGER" = "apt" ]; then
        print_info "Updating package lists..."
        $SUDO apt-get update -qq

        print_info "Installing required packages: ${SYSTEM_PACKAGES[*]}"
        $SUDO apt-get install -y "${SYSTEM_PACKAGES[@]}"

        print_success "System dependencies installed"
    else
        print_warning "Unknown package manager - please install manually:"
        for pkg in "${SYSTEM_PACKAGES[@]}"; do
            print_info "  - $pkg"
        done

        if ! ask_yes_no "Have you installed these dependencies?"; then
            exit 1
        fi
    fi
}

# Detect serial devices
detect_serial_devices() {
    print_header "Detecting Serial Devices"

    local devices=()

    # Look for common serial device patterns
    for dev in /dev/ttyUSB* /dev/ttyACM* /dev/ttyAMA* /dev/ttyS*; do
        if [ -e "$dev" ]; then
            devices+=("$dev")
        fi
    done

    if [ ${#devices[@]} -eq 0 ]; then
        print_warning "No serial devices detected"
        print_info "Your RS-485 adapter may not be connected yet"
        SERIAL_DEVICE=""
    else
        print_info "Found ${#devices[@]} serial device(s):"
        echo

        # Display devices with additional information
        for i in "${!devices[@]}"; do
            local dev="${devices[$i]}"
            local info=""

            # Try to get device info from udev
            if command -v udevadm &> /dev/null; then
                # Get manufacturer and model if available
                local id_vendor=$(udevadm info -q property -n "$dev" 2>/dev/null | grep "^ID_VENDOR=" | cut -d= -f2)
                local id_model=$(udevadm info -q property -n "$dev" 2>/dev/null | grep "^ID_MODEL=" | cut -d= -f2)
                local id_serial=$(udevadm info -q property -n "$dev" 2>/dev/null | grep "^ID_SERIAL_SHORT=" | cut -d= -f2)

                if [ -n "$id_vendor" ] || [ -n "$id_model" ]; then
                    info="${id_vendor:+$id_vendor }${id_model:+$id_model }"
                    [ -n "$id_serial" ] && info="${info}(SN: $id_serial)"
                fi
            fi

            # Check for symlinks in /dev/serial/by-id/
            if [ -z "$info" ] && [ -d /dev/serial/by-id ]; then
                for link in /dev/serial/by-id/*; do
                    if [ -e "$link" ] && [ "$(readlink -f "$link")" = "$dev" ]; then
                        info=$(basename "$link")
                        break
                    fi
                done
            fi

            # Display device with info
            if [ -n "$info" ]; then
                echo "  $((i+1)). $dev - $info"
            else
                echo "  $((i+1)). $dev"
            fi
        done

        echo

        # Force user to select even with one device
        while true; do
            read -p "Select device number [1-${#devices[@]}]: " selection
            if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -le "${#devices[@]}" ]; then
                SERIAL_DEVICE="${devices[$((selection-1))]}"
                print_success "Selected: $SERIAL_DEVICE"
                break
            else
                print_error "Invalid selection"
            fi
        done
    fi
}

# Create udev rule for ttyHeatPump symlink
create_device_symlink() {
    print_header "Creating Device Symlink"

    if [ -z "$SERIAL_DEVICE" ]; then
        print_info "No serial device selected, skipping symlink creation"
        return
    fi

    local udev_rule_file="/etc/udev/rules.d/99-waterfurnace-heatpump.rules"

    # Check if symlink already exists
    if [ -f "$udev_rule_file" ]; then
        print_warning "Device symlink rule already exists"

        # Show current symlink if it exists
        local current_target=""
        if [ -e /dev/ttyHeatPump ]; then
            current_target=$(readlink -f /dev/ttyHeatPump)
            print_info "Current symlink: /dev/ttyHeatPump -> $current_target"
        fi

        # Check if selected device differs from current symlink target
        local selected_device=$(readlink -f "$SERIAL_DEVICE")
        if [ -n "$current_target" ] && [ "$selected_device" != "$current_target" ]; then
            print_warning "Selected device ($SERIAL_DEVICE) differs from current symlink target ($current_target)"
            if ! ask_yes_no "Update symlink to point to $SERIAL_DEVICE?" "y"; then
                print_info "Keeping symlink pointed to $current_target"
                SERIAL_DEVICE="/dev/ttyHeatPump"
                return
            fi
            # User wants to update - proceed to reconfiguration
        else
            # Same device - ask if they want to reconfigure anyway
            if ! ask_yes_no "Would you like to reconfigure the symlink?" "n"; then
                print_info "Keeping existing symlink configuration"
                if [ -e /dev/ttyHeatPump ]; then
                    SERIAL_DEVICE="/dev/ttyHeatPump"
                fi
                return
            fi
        fi
    else
        if ! ask_yes_no "Create /dev/ttyHeatPump symlink for easy access?" "y"; then
            print_info "Skipping symlink creation"
            return
        fi
    fi

    local kernel_name=$(basename "$SERIAL_DEVICE")

    # Get device attributes for a more robust rule
    local attrs=""
    if command -v udevadm &> /dev/null; then
        local id_serial=$(udevadm info -q property -n "$SERIAL_DEVICE" 2>/dev/null | grep "^ID_SERIAL_SHORT=" | cut -d= -f2)
        local id_vendor_id=$(udevadm info -q property -n "$SERIAL_DEVICE" 2>/dev/null | grep "^ID_VENDOR_ID=" | cut -d= -f2)
        local id_model_id=$(udevadm info -q property -n "$SERIAL_DEVICE" 2>/dev/null | grep "^ID_MODEL_ID=" | cut -d= -f2)

        # Build attribute matching for more reliable device identification
        if [ -n "$id_serial" ]; then
            attrs="ATTRS{serial}==\"$id_serial\", "
        elif [ -n "$id_vendor_id" ] && [ -n "$id_model_id" ]; then
            attrs="ATTRS{idVendor}==\"$id_vendor_id\", ATTRS{idProduct}==\"$id_model_id\", "
        fi
    fi

    print_info "Creating udev rule: $udev_rule_file"

    # Create udev rule
    if [ -n "$attrs" ]; then
        # More robust rule using device attributes
        cat <<EOF | $SUDO tee "$udev_rule_file" > /dev/null
# WaterFurnace Aurora Heat Pump Serial Device
# This rule creates a persistent /dev/ttyHeatPump symlink
SUBSYSTEM=="tty", $attrs SYMLINK+="ttyHeatPump", MODE="0666", GROUP="dialout"
EOF
    else
        # Fallback to kernel name matching
        cat <<EOF | $SUDO tee "$udev_rule_file" > /dev/null
# WaterFurnace Aurora Heat Pump Serial Device
# This rule creates a persistent /dev/ttyHeatPump symlink
KERNEL=="$kernel_name", SUBSYSTEM=="tty", SYMLINK+="ttyHeatPump", MODE="0666", GROUP="dialout"
EOF
    fi

    # Reload udev rules
    print_info "Reloading udev rules..."
    $SUDO udevadm control --reload-rules
    $SUDO udevadm trigger --subsystem-match=tty

    # Wait a moment for udev to process
    sleep 1

    # Verify symlink was created
    if [ -e /dev/ttyHeatPump ]; then
        print_success "Symlink created: /dev/ttyHeatPump -> $(readlink -f /dev/ttyHeatPump)"
        SERIAL_DEVICE="/dev/ttyHeatPump"
    else
        print_warning "Symlink not yet available, but udev rule is configured"
        print_info "It will be available after the next device reconnection"
    fi
}

# Configure user permissions
configure_user_permissions() {
    print_header "Configuring User Permissions"

    local current_user="${SUDO_USER:-$USER}"

    print_info "To access serial devices, user '$current_user' needs to be in the 'dialout' group"

    if groups "$current_user" | grep -q '\bdialout\b'; then
        print_success "User '$current_user' is already in the dialout group"
    else
        if ask_yes_no "Add user '$current_user' to the dialout group?" "y"; then
            $SUDO usermod -a -G dialout "$current_user"
            print_success "User added to dialout group"
            print_warning "You will need to log out and back in for this change to take effect"
            NEED_RELOGIN=true
        fi
    fi
}

# Check Ruby version
check_ruby_version() {
    print_header "Checking Ruby Version"

    if ! command -v ruby &> /dev/null; then
        print_error "Ruby is not installed or not in PATH"
        exit 1
    fi

    RUBY_VERSION=$(ruby -e 'puts RUBY_VERSION')
    print_info "Found Ruby version: $RUBY_VERSION"

    # Compare versions
    if [ "$(printf '%s\n' "$REQUIRED_RUBY_MIN" "$RUBY_VERSION" | sort -V | head -n1)" != "$REQUIRED_RUBY_MIN" ]; then
        print_error "Ruby version $RUBY_VERSION is too old (minimum: $REQUIRED_RUBY_MIN)"
        exit 1
    fi

    # Check if version is too new
    RUBY_MAJOR_MINOR=$(echo $RUBY_VERSION | cut -d. -f1-2)
    if [ "$(printf '%s\n' "$RUBY_MAJOR_MINOR" "$REQUIRED_RUBY_MAX" | sort -V | tail -n1)" != "$REQUIRED_RUBY_MAX" ]; then
        print_warning "Ruby version $RUBY_VERSION may be too new (recommended: $REQUIRED_RUBY_MIN-$REQUIRED_RUBY_MAX)"
        if ! ask_yes_no "Continue anyway?"; then
            exit 1
        fi
    else
        print_success "Ruby version is compatible"
    fi
}

# Install the gem
install_gem() {
    print_header "Installing WaterFurnace Aurora Gem"

    print_info "Installing gems: ${GEMS_TO_INSTALL[*]}"
    if $SUDO gem install "${GEMS_TO_INSTALL[@]}" --no-doc --platform=ruby; then
        print_success "Gems installed successfully"
    else
        print_error "Failed to install gems"
        exit 1
    fi
}

# Test if installed gems are working
test_gems() {
    print_header "Testing Installed Gems"

    local test_passed=true

    for gem_name in "${GEMS_TO_INSTALL[@]}"; do
        local require_name="${gem_name}"

        print_info "Testing ${gem_name}..."

        # Run Ruby in a subprocess to isolate crashes
        ruby -e "begin; require '${require_name}'; rescue LoadError => e; puts e.message; exit 1; end" >/dev/null 2>&1 &
        local pid=$!
        wait $pid 2>/dev/null
        local exit_code=$?

        if [ $exit_code -eq 0 ]; then
            print_success "${gem_name} loaded successfully"
        else
            print_error "${gem_name} failed to load"
            test_passed=false
        fi
    done

    echo

    if [ "$test_passed" = true ]; then
        print_success "All gems are working correctly!"
    else
        print_warning "Some gems failed to load - installation may have issues"
        if ! ask_yes_no "Continue anyway?" "n"; then
            exit 1
        fi
    fi
}

# Test hardware communication with heat pump
test_hardware_communication() {
    print_header "Testing Hardware Communication"

    if [ -z "$SERIAL_DEVICE" ]; then
        print_warning "No serial device configured"
        if ! ask_yes_no "Skip hardware communication test?" "y"; then
            read -p "Enter serial device path (e.g., /dev/ttyHeatPump): " SERIAL_DEVICE
        else
            print_info "Skipping hardware communication test"
            return
        fi
    fi

    if [ ! -e "$SERIAL_DEVICE" ]; then
        print_warning "Serial device $SERIAL_DEVICE not found"
        print_info "Your heat pump may not be connected yet"
        if ! ask_yes_no "Skip hardware communication test?" "y"; then
            print_info "Skipping hardware communication test"
            return
        fi
    fi

    print_info "Testing communication with heat pump at $SERIAL_DEVICE..."
    print_info "Querying Model Number and Serial Number..."
    echo

    # Try to fetch model number and serial number (full ranges for ASCII strings)
    local test_output
    test_output=$(aurora_fetch "$SERIAL_DEVICE" 92-103,105-109 2>&1)
    local exit_code=$?

    if [ $exit_code -eq 0 ]; then
        print_success "Successfully communicated with heat pump!"
        echo
        echo "$test_output"
        echo
        print_info "Your WaterFurnace Aurora system is responding correctly"
    else
        print_error "Failed to communicate with heat pump"
        echo
        echo "Error output:"
        echo "$test_output"
        echo
        print_warning "This could mean:"
        print_info "  • The heat pump is not connected to $SERIAL_DEVICE"
        print_info "  • The RS-485 adapter is not working properly"
        print_info "  • The device permissions are not set correctly"
        print_info "  • The heat pump is powered off"
        echo

        if ! ask_yes_no "Continue with installation anyway?" "y"; then
            print_info "Installation cancelled"
            echo
            print_info "Troubleshooting tips:"
            print_info "  1. Check that your RS-485 adapter is connected"
            print_info "  2. Verify the heat pump is powered on"
            print_info "  3. Check device permissions: ls -l $SERIAL_DEVICE"
            print_info "  4. Try manually: aurora_fetch $SERIAL_DEVICE 2"
            exit 1
        fi
    fi
}

# Install MQTT broker
install_mqtt_broker() {
    print_header "MQTT Broker Setup"

    print_info "The WaterFurnace Aurora MQTT bridge requires an MQTT broker"
    echo
    echo "If you're using home automation software, you may already have one:"
    echo "  • Home Assistant - Includes Mosquitto MQTT Broker add-on"
    echo "  • OpenHAB - Often uses Mosquitto installed separately"
    echo "  • Other systems - Many include or support Mosquitto MQTT broker"
    echo
    echo "You can either install Mosquitto locally or point to an existing broker"
    echo

    if command -v mosquitto &> /dev/null; then
        print_success "Mosquitto is already installed"

        # Check if security configuration exists
        local config_file="/etc/mosquitto/conf.d/local-only.conf"
        if [ ! -f "$config_file" ]; then
            print_warning "Mosquitto is installed but not configured for localhost-only access"
            if ask_yes_no "Would you like to configure Mosquitto to listen on localhost only (recommended)?" "y"; then
                print_info "Creating security configuration..."
                cat <<EOF | $SUDO tee "$config_file" > /dev/null
# WaterFurnace Aurora - Localhost only configuration
# This restricts Mosquitto to accept connections only from localhost
# for security purposes (prevents external network access)
listener 1883 127.0.0.1
allow_anonymous true
EOF
                $SUDO systemctl restart mosquitto
                print_success "Mosquitto configured for localhost-only access"
            fi
        fi

        MQTT_HOST="localhost"
        return
    fi

    if ask_yes_no "Would you like to install Mosquitto MQTT broker on this system?" "y"; then
        if [ "$PACKAGE_MANAGER" = "apt" ]; then
            print_info "Installing MQTT packages: ${MQTT_PACKAGES[*]}"
            $SUDO apt-get install -y "${MQTT_PACKAGES[@]}"

            # Ask user about network access configuration
            echo
            print_warning "IMPORTANT: Mosquitto can be configured for different access levels:"
            print_info "  • Localhost only (127.0.0.1) - Most secure, only local connections"
            print_info "  • All interfaces (0.0.0.0) - Allows remote connections (less secure)"
            echo

            if ask_yes_no "Configure Mosquitto to listen on localhost only (recommended for security)?" "y"; then
                # Configure for localhost only
                print_info "Configuring Mosquitto for localhost-only access..."
                local config_file="/etc/mosquitto/conf.d/local-only.conf"
                cat <<EOF | $SUDO tee "$config_file" > /dev/null
# WaterFurnace Aurora - Localhost only configuration
# This restricts Mosquitto to accept connections only from localhost
# for security purposes (prevents external network access)
listener 1883 127.0.0.1
allow_anonymous true
EOF
                print_success "Mosquitto configured for localhost-only access"
                MQTT_HOST="localhost"
            else
                # Configure for all interfaces (with warning)
                print_warning "Configuring Mosquitto to accept connections from all network interfaces"
                print_info "This allows remote MQTT clients but is less secure"
                local config_file="/etc/mosquitto/conf.d/allow-external.conf"
                cat <<EOF | $SUDO tee "$config_file" > /dev/null
# WaterFurnace Aurora - Allow external connections
# WARNING: This allows unauthenticated connections from any network interface
# Consider adding authentication for production use
listener 1883
allow_anonymous true
EOF
                print_success "Mosquitto configured to allow external connections"
                MQTT_HOST="0.0.0.0"
            fi

            $SUDO systemctl enable mosquitto
            $SUDO systemctl start mosquitto
            print_success "Mosquitto installed and started"
        else
            print_warning "Cannot automatically install Mosquitto on this system"
            MQTT_HOST=""
        fi
    else
        print_info "Skipping MQTT broker installation"
        MQTT_HOST=""
    fi
}

# Setup MQTT bridge service
setup_mqtt_bridge() {
    print_header "MQTT Bridge Setup"

    local current_user="${SUDO_USER:-$USER}"
    local user_home=$(eval echo ~$current_user)
    local service_file="/etc/systemd/system/aurora_mqtt_bridge.service"

    # Variables to hold config defaults (will be overridden by existing config if found)
    local existing_serial="$SERIAL_DEVICE"
    local existing_host="localhost"
    local existing_port="1883"
    local existing_user=""
    local existing_password=""
    local existing_device_name="WaterFurnace"
    local existing_web_aid_port=""
    local existing_app_env="production"

    # Check if service already exists
    if [ -f "$service_file" ]; then
        print_warning "MQTT bridge service already exists"

        if ! ask_yes_no "Would you like to reconfigure the service?" "n"; then
            print_info "Keeping existing service configuration"
            return
        fi

        # URL decode a string (reverse of url_encode)
        url_decode() {
            local encoded="$1"
            printf '%b' "${encoded//%/\\x}"
        }

        # Parse existing configuration from service file
        print_info "Reading existing configuration..."
        local exec_start=$(grep "^ExecStart=" "$service_file" | sed 's/^ExecStart=//')

        if [ -n "$exec_start" ]; then
            # Extract serial device (first argument after command)
            existing_serial=$(echo "$exec_start" | awk '{print $2}')

            # Extract MQTT URI (second argument, unescape %% to %)
            local mqtt_uri_escaped=$(echo "$exec_start" | awk '{print $3}')
            local mqtt_uri="${mqtt_uri_escaped//%%/%}"

            # Parse MQTT URI to extract host, port, username, password
            if [[ "$mqtt_uri" =~ mqtt://([^:]+):(.+)@([^:]+):([0-9]+)/ ]]; then
                # Has username and password
                existing_user=$(url_decode "${BASH_REMATCH[1]}")
                existing_password=$(url_decode "${BASH_REMATCH[2]}")
                existing_host="${BASH_REMATCH[3]}"
                existing_port="${BASH_REMATCH[4]}"
            elif [[ "$mqtt_uri" =~ mqtt://([^:]+):([0-9]+)/ ]]; then
                # No username/password
                existing_host="${BASH_REMATCH[1]}"
                existing_port="${BASH_REMATCH[2]}"
            fi

            # Extract device name (from --device-name argument)
            if [[ "$exec_start" =~ --device-name[[:space:]]+\"([^\"]+)\" ]]; then
                existing_device_name="${BASH_REMATCH[1]}"
            elif [[ "$exec_start" =~ --device-name[[:space:]]+([^[:space:]]+) ]]; then
                existing_device_name="${BASH_REMATCH[1]}"
            fi

            # Extract web aid tool port (from --web-aid-tool argument)
            if [[ "$exec_start" =~ --web-aid-tool=([0-9]+) ]]; then
                existing_web_aid_port="${BASH_REMATCH[1]}"
            fi

            print_success "Found existing configuration"
        fi

        # Extract APP_ENV if set
        local app_env_line=$(grep "^Environment=" "$service_file" | grep "APP_ENV")
        if [[ "$app_env_line" =~ APP_ENV=([^ ]+) ]]; then
            existing_app_env="${BASH_REMATCH[1]}"
        fi

        # Stop the service if it's running
        if $SUDO systemctl is-active --quiet aurora_mqtt_bridge.service; then
            print_info "Stopping existing service..."
            $SUDO systemctl stop aurora_mqtt_bridge.service
        fi
    else
        if ! ask_yes_no "Would you like to set up the MQTT bridge service?" "y"; then
            print_info "Skipping MQTT bridge setup"
            return
        fi
    fi

    # Collect configuration
    print_header "MQTT Bridge Configuration"

    # Serial device
    if [ -z "$SERIAL_DEVICE" ]; then
        if [ -n "$existing_serial" ]; then
            read -p "Enter serial device path [$existing_serial]: " SERIAL_DEVICE
            SERIAL_DEVICE=${SERIAL_DEVICE:-$existing_serial}
        else
            read -p "Enter serial device path (e.g., /dev/ttyUSB0): " SERIAL_DEVICE
        fi
    fi

    # MQTT host
    if [ -z "$MQTT_HOST" ]; then
        read -p "Enter MQTT broker hostname [$existing_host]: " MQTT_HOST
        MQTT_HOST=${MQTT_HOST:-$existing_host}
    fi

    # MQTT port
    read -p "Enter MQTT broker port [$existing_port]: " MQTT_PORT
    MQTT_PORT=${MQTT_PORT:-$existing_port}

    # MQTT username (optional)
    if [ -n "$existing_user" ]; then
        read -p "Enter MQTT username [$existing_user]: " MQTT_USER
        MQTT_USER=${MQTT_USER:-$existing_user}
    else
        read -p "Enter MQTT username (leave blank if none): " MQTT_USER
    fi

    # MQTT password (optional)
    if [ -n "$MQTT_USER" ]; then
        if [ -n "$existing_password" ] && [ "$MQTT_USER" = "$existing_user" ]; then
            read -s -p "Enter MQTT password (leave blank to keep existing): " MQTT_PASSWORD
            echo
            # If blank, use existing password
            if [ -z "$MQTT_PASSWORD" ]; then
                MQTT_PASSWORD="$existing_password"
                print_info "Keeping existing password"
            fi
        else
            read -s -p "Enter MQTT password: " MQTT_PASSWORD
            echo
        fi
    fi

    # Device name for MQTT
    read -p "Enter device name for MQTT [$existing_device_name]: " DEVICE_NAME
    DEVICE_NAME=${DEVICE_NAME:-$existing_device_name}

    # Web Aid Tool (optional web interface)
    if [ -n "$existing_web_aid_port" ]; then
        if ask_yes_no "Enable web aid tool (web interface)? Currently enabled on port $existing_web_aid_port" "y"; then
            read -p "Enter web aid tool port [$existing_web_aid_port]: " WEB_AID_PORT
            WEB_AID_PORT=${WEB_AID_PORT:-$existing_web_aid_port}
        else
            WEB_AID_PORT=""
        fi
    else
        if ask_yes_no "Enable web aid tool (provides web interface)?" "n"; then
            read -p "Enter web aid tool port [4567]: " WEB_AID_PORT
            WEB_AID_PORT=${WEB_AID_PORT:-4567}
        else
            WEB_AID_PORT=""
        fi
    fi

    # Check for HTML files if web aid tool is enabled
    if [ -n "$WEB_AID_PORT" ]; then
        local html_dir="$user_home/waterfurnace_aurora/html"
        if [ ! -d "$html_dir" ] || [ ! -f "$html_dir/index.htm" ]; then
            print_warning "Web aid tool HTML files not found in ~/waterfurnace_aurora/html"
            print_info "You'll need to download them using:"
            print_info "  cd ~/waterfurnace_aurora"
            print_info "  bash contrib/grab_awl_assets.sh [AWL_IP_ADDRESS]"
            print_info "The web aid tool will not work until these files are present"
        fi
    fi

    echo
    print_info "Configuration summary:"
    echo "  Serial Device: $SERIAL_DEVICE"
    echo "  MQTT Broker: $MQTT_HOST:$MQTT_PORT"
    [ -n "$MQTT_USER" ] && echo "  MQTT User: $MQTT_USER"
    echo "  Device Name: $DEVICE_NAME"
    [ -n "$WEB_AID_PORT" ] && echo "  Web Aid Tool: http://localhost:$WEB_AID_PORT"
    echo

    # URL encode a string for use in URIs
    url_encode() {
        local string="$1"
        local strlen=${#string}
        local encoded=""
        local pos c o

        for (( pos=0 ; pos<strlen ; pos++ )); do
            c=${string:$pos:1}
            case "$c" in
                [-_.~a-zA-Z0-9] ) o="${c}" ;;
                * ) printf -v o '%%%02x' "'$c" ;;
            esac
            encoded+="${o}"
        done
        echo "${encoded}"
    }

    # Build MQTT URI
    local mqtt_uri
    if [ -n "$MQTT_USER" ] && [ -n "$MQTT_PASSWORD" ]; then
        local encoded_user=$(url_encode "$MQTT_USER")
        local encoded_password=$(url_encode "$MQTT_PASSWORD")
        mqtt_uri="mqtt://${encoded_user}:${encoded_password}@${MQTT_HOST}:${MQTT_PORT}/"
    else
        mqtt_uri="mqtt://${MQTT_HOST}:${MQTT_PORT}/"
    fi

    # Escape percent signs for systemd unit files (% must be %% in systemd)
    local systemd_mqtt_uri="${mqtt_uri//%/%%}"

    # Build command line (correct format: aurora_mqtt_bridge <serial> <mqtt_uri> [--device-name NAME] [--web-aid-tool=PORT])
    local cmd="aurora_mqtt_bridge $SERIAL_DEVICE $systemd_mqtt_uri --device-name \"$DEVICE_NAME\""
    [ -n "$WEB_AID_PORT" ] && cmd="$cmd --web-aid-tool=$WEB_AID_PORT"

    # Create working directory for the service
    local work_dir="$user_home/waterfurnace_aurora"

    print_info "Working directory will be: $work_dir"

    # Ensure user's home directory has execute permissions for systemd to access it
    # Systemd needs to traverse the home directory to reach the working directory
    local home_perms=$(stat -c "%a" "$user_home" 2>/dev/null || stat -f "%Lp" "$user_home" 2>/dev/null)
    if [ -n "$home_perms" ]; then
        print_info "User home directory permissions: $home_perms"
        # Check if 'others' have execute permission (last digit must be odd for x permission)
        local other_perms=${home_perms: -1}
        if [ $((other_perms & 1)) -eq 0 ]; then
            print_warning "User home directory lacks execute permission for systemd"
            print_info "Adding execute permission to home directory: $user_home"
            $SUDO chmod o+x "$user_home"

            # Verify the change was applied
            local new_perms=$(stat -c "%a" "$user_home" 2>/dev/null || stat -f "%Lp" "$user_home" 2>/dev/null)
            print_success "Home directory permissions updated: $home_perms → $new_perms"

            # Double-check that execute permission was actually added
            local new_other_perms=${new_perms: -1}
            if [ $((new_other_perms & 1)) -eq 0 ]; then
                print_error "Failed to add execute permission to home directory"
                print_warning "You may need to manually run: sudo chmod 701 $user_home"
            fi
        else
            print_success "Home directory already has correct permissions"
        fi
    fi

    if [ ! -d "$work_dir" ]; then
        # Create as the actual user, not root
        sudo -u "$current_user" mkdir -p "$work_dir"
        print_success "Created working directory: $work_dir"
    fi

    # Ensure correct ownership and permissions
    # The directory must be owned by the user and have execute permissions
    $SUDO chown "$current_user:$current_user" "$work_dir"
    $SUDO chmod 755 "$work_dir"

    # Verify the permissions were set correctly
    local dir_perms=$(stat -c "%a" "$work_dir" 2>/dev/null || stat -f "%Lp" "$work_dir" 2>/dev/null)
    local dir_owner=$(stat -c "%U" "$work_dir" 2>/dev/null || stat -f "%Su" "$work_dir" 2>/dev/null)
    print_success "Working directory permissions: $dir_perms (owner: $dir_owner)"

    # Only add mosquitto.service dependency if Mosquitto is installed locally
    local after_services="network.target"
    if command -v mosquitto &> /dev/null; then
        after_services="$after_services mosquitto.service"
        print_info "Local Mosquitto detected - service will wait for it to start"
    fi

    print_info "Creating service file: $service_file"

    cat <<EOF | $SUDO tee "$service_file" > /dev/null
[Unit]
Description=WaterFurnace Aurora MQTT Bridge
After=$after_services
Wants=network-online.target

[Service]
Type=simple
User=$current_user
WorkingDirectory=$work_dir
Environment=APP_ENV=$existing_app_env
ExecStart=$cmd
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    print_success "Service file created"

    if ask_yes_no "Enable service to start on boot?" "y"; then
        $SUDO systemctl daemon-reload
        $SUDO systemctl enable aurora_mqtt_bridge.service
        print_success "Service enabled"
    fi

    if ask_yes_no "Start service now?" "y"; then
        if [ "$NEED_RELOGIN" = true ]; then
            print_warning "Cannot start service now - you need to log out and back in first"
            print_info "After re-login, start with: sudo systemctl start aurora_mqtt_bridge.service"
        else
            $SUDO systemctl start aurora_mqtt_bridge.service
            sleep 2
            if $SUDO systemctl is-active --quiet aurora_mqtt_bridge.service; then
                print_success "Service started successfully"
            else
                print_error "Service failed to start"
                print_info "Check logs with: sudo journalctl -u aurora_mqtt_bridge.service -f"
            fi
        fi
    fi
}


# Display next steps
show_next_steps() {
    print_header "Installation Complete!"

    print_success "WaterFurnace Aurora has been installed"

    echo -e "\n${BLUE}Next Steps:${NC}\n"

    if [ "$NEED_RELOGIN" = true ]; then
        echo "  • Log out and log back in to apply group membership changes"
        echo "  • Start the MQTT bridge service:"
        echo -e "    ${YELLOW}sudo systemctl start aurora_mqtt_bridge.service${NC}"
    else
        echo "  • Check service status:"
        echo -e "    ${YELLOW}sudo systemctl status aurora_mqtt_bridge.service${NC}"
    fi

    # Only show mosquitto_sub if it's installed locally
    if command -v mosquitto_sub &> /dev/null; then
        echo "  • Monitor MQTT messages (using local Mosquitto client):"
        echo -e "    ${YELLOW}mosquitto_sub -h $MQTT_HOST -t 'homie/$DEVICE_NAME/#' -v${NC}"
    fi

    echo "  • View service logs:"
    echo -e "    ${YELLOW}sudo journalctl -u aurora_mqtt_bridge.service -f${NC}"

    # Check if web aid tool is enabled
    local service_file="/etc/systemd/system/aurora_mqtt_bridge.service"
    if [ -f "$service_file" ]; then
        local exec_start=$(grep "^ExecStart=" "$service_file" 2>/dev/null)
        if [[ "$exec_start" =~ --web-aid-tool=([0-9]+) ]]; then
            local web_aid_port="${BASH_REMATCH[1]}"
            echo -e "\n${BLUE}Web Aid Tool:${NC}\n"

            # Get the actual user's home directory (not root's, even if running with sudo)
            local current_user="${SUDO_USER:-$USER}"
            local user_home=$(eval echo ~$current_user)
            if [ ! -d "$user_home/waterfurnace_aurora/html" ] || [ ! -f "$user_home/waterfurnace_aurora/html/index.htm" ]; then
                echo -e "${YELLOW}⚠${NC}  Web aid tool is enabled but HTML files are missing!"
                echo "   Download the required files:"
                echo -e "   ${YELLOW}cd ~/waterfurnace_aurora${NC}"
                echo -e "   ${YELLOW}bash contrib/grab_awl_assets.sh [AWL_IP_ADDRESS]${NC}"
                echo "   (Replace AWL_IP_ADDRESS with your Aurora Web Link IP, default: 172.20.10.1)"
            else
                echo -e "  Web interface available at: ${YELLOW}http://localhost:$web_aid_port${NC}"
                echo "  (Accessible from other devices if APP_ENV=production is set)"
            fi
        fi
    fi

    echo -e "\n${BLUE}Command-line Tools:${NC}\n"
    echo -e "  • ${YELLOW}aurora_fetch${NC} - Query specific registers"
    echo -e "  • ${YELLOW}aurora_monitor${NC} - Monitor ModBus traffic"
    echo -e "  • ${YELLOW}aurora_mock${NC} - Simulate ABC for testing"
    echo -e "  • ${YELLOW}aurora_mqtt_bridge${NC} - MQTT bridge service"

    echo -e "\n${BLUE}Documentation:${NC}\n"
    echo "  • Getting Started: GETTING_STARTED.md"
    echo "  • Hardware Setup: HARDWARE.md"
    echo "  • Home Assistant: docs/integration/home-assistant.md"
    echo "  • Troubleshooting: docs/troubleshooting.md"

    echo -e "\n${BLUE}Support This Project:${NC}\n"
    echo "  If you find this project helpful, consider supporting its development:"
    echo -e "  • Buy Me a Coffee: ${YELLOW}https://buymeacoffee.com/ccutrer${NC}"
    echo -e "  • Ko-fi: ${YELLOW}https://ko-fi.com/ccutrer${NC}"
    echo -e "  • thanks.dev: ${YELLOW}https://thanks.dev/u/gh/ccutrer${NC}"
    echo -e "  • Venmo: ${YELLOW}https://account.venmo.com/u/ccutrer${NC}"
    echo -e "  • PayPal: ${YELLOW}https://paypal.me/ccutrer${NC}"

    echo -e "\n${GREEN}Thank you for using WaterFurnace Aurora gem!${NC}\n"
}

# Main installation flow
main() {
    # Initialize variables
    NEED_RELOGIN=false
    SERIAL_DEVICE=""
    MQTT_HOST=""

    print_header "WaterFurnace Aurora Installation Script"

    echo "This script will install and configure the WaterFurnace Aurora gem"
    echo "for monitoring and controlling your WaterFurnace geothermal heat"
    echo "pump."
    echo

    if ! ask_yes_no "Continue with installation?" "y"; then
        echo "Installation cancelled."
        exit 0
    fi

    # Run installation steps
    detect_platform
    check_privileges
    install_dependencies
    detect_serial_devices
    create_device_symlink
    configure_user_permissions
    check_ruby_version
    install_gem
    test_gems
    test_hardware_communication
    install_mqtt_broker
    setup_mqtt_bridge
    show_next_steps
}

# Run main function
main "$@"
