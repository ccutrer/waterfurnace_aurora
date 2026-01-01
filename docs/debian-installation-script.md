# WaterFurnace Aurora Debian/Ubuntu Installation Script Guide

This guide walks you through using the automated installation script (`install.sh`) for WaterFurnace Aurora on Debian and Ubuntu-based systems, including Raspberry Pi.

## Overview

The installation script provides a guided, interactive setup process that:

- Detects your platform and installs system dependencies
- Identifies RS-485 serial devices automatically
- Creates persistent device symlinks for easy access
- Configures user permissions for serial device access
- Installs and tests the WaterFurnace Aurora Ruby gem
- Verifies hardware communication with your heat pump
- Optionally installs and configures Mosquitto MQTT broker
- Sets up systemd services for automated operation
- Provides a complete configuration for immediate use

## Prerequisites

### Hardware Requirements

- **Raspberry Pi** (recommended) or any Debian/Ubuntu-based Linux system
- **RS-485 USB adapter** - Any adapter **except** those based on the MAX485 chip
  - Recommended: [USB to RS485 Converter](https://www.amazon.com/dp/B07B416CPK) or [alternative](https://www.amazon.com/dp/B081MB6PN2)
- **Network cable** (CAT5/CAT6) for connecting to your heat pump
- **WaterFurnace heat pump** with AID Tool port or Aurora Web Link (AWL)

### Supported Operating Systems

The script is optimized for:
- Raspberry Pi OS (Raspbian)
- Debian 11+ (Bullseye and newer)
- Ubuntu 20.04+ (Focal and newer)

**Developed and tested on:**
- Debian Trixie (Debian 13)
- Debian Bookworm (Debian 12)

Other Debian/Ubuntu-based distributions should work but may require manual dependency installation.

### Required Ruby Version

- **Minimum**: Ruby 2.5
- **Recommended**: Ruby 2.5 - 2.7
- **Tested and working**: Ruby 3.3.7

The script will check your Ruby version and warn if it's outside the recommended range. While Ruby 3.x versions may show a warning, the gem has been confirmed to work on Ruby 3.3.7.

## Preparing Your Hardware

### Step 1: Create the RS-485 Cable

You'll need to create a cable to connect your USB RS-485 adapter to the heat pump:

1. **Option A**: Cut one end off an existing ethernet patch cable
2. **Option B**: Take CAT5 cable and crimp an RJ45 jack on one end

Ensure the jack end is wired for [TIA-568-B standard](https://upload.wikimedia.org/wikipedia/commons/6/60/RJ-45_TIA-568B_Left.png).

### Step 2: Wire the RS-485 Connections

At the cut/stripped end of the cable:

1. Remove jacket to expose the wires
2. Identify the following wire pairs (for TIA-568-B):
   - **RS-485 A+ (positive)**: Twist together pin 1 (white-orange) and pin 3 (white-green)
   - **RS-485 B- (negative)**: Twist together pin 2 (orange) and pin 4 (blue)

3. Connect to your USB RS-485 adapter:
   - Twisted white wires → **A+** or **TXD+** terminal
   - Twisted solid wires → **B-** or **TXD-** terminal
   - Leave RXD+, RXD-, and GND unconnected

**WARNING**: Pins 5, 6, 7, and 8 carry 24VAC power from the thermostat bus. **DO NOT** connect these to anything! Shorting them can blow a fuse in your heat pump or damage the ABC board.

### Step 3: Connect the Cable

1. Plug the RJ45 jack into the **AID Tool port** on your heat pump
   - OR if you have an AWL, plug into the AID Tool port on the AWL
2. Plug the USB RS-485 adapter into your Raspberry Pi or Linux computer

See the [README.md](../README.md) for photos of proper cable connections.

## Installation Process

### Step 1: Run the Installation Script

**Option A: One-line installation** (recommended for quick setup)

Run the installation script directly:

```bash
curl -fsSL https://raw.githubusercontent.com/ccutrer/waterfurnace_aurora/main/install.sh | bash
```

**Option B: Download and review** (recommended for security-conscious users)

Download the script, review it, then run:

```bash
curl -O https://raw.githubusercontent.com/ccutrer/waterfurnace_aurora/main/install.sh
chmod +x install.sh
./install.sh
```

**Option C: From cloned repository**

If you've already cloned the repository:

```bash
cd waterfurnace_aurora
chmod +x install.sh
./install.sh
```

The script will guide you through each step of the installation process.

### Step 2: Follow the Interactive Prompts

The installation is divided into several phases. Here's what to expect:

#### Phase 1: Platform Detection

The script automatically detects:
- Your operating system and version
- Whether you're running on a Raspberry Pi
- Your package manager (apt for Debian/Ubuntu)

**What you'll see:**
```
=================================================================
Detecting Platform
=================================================================

✓  Detected Raspberry Pi: Raspberry Pi Zero W Rev 1.1
ℹ  Operating System: Raspbian GNU/Linux 13 (trixie)
✓  Supported distribution detected
```

**Action required**: Confirm to continue if prompted.

#### Phase 2: Installing Dependencies

The script installs required system packages:
- `ruby` - Ruby interpreter
- `ruby-dev` - Ruby development headers

**Note**: Before installing dependencies, you may be prompted for your sudo password:
```
⚠  This script requires sudo privileges for installing system packages
[sudo] password for pi:
```

**What you'll see:**
```
=================================================================
Installing System Dependencies
=================================================================

ℹ  Updating package lists...
ℹ  Installing required packages: ruby ruby-dev
✓  System dependencies installed
```

**Action required**:
- Enter your sudo password when prompted
- The rest is automatic once sudo access is granted

#### Phase 3: Serial Device Detection

The script scans for RS-485 adapters and displays detailed information about each device found.

**What you'll see** (example - your list will vary based on your system):
```
=================================================================
Detecting Serial Devices
=================================================================

ℹ  Found 3 serial device(s):

  1. /dev/ttyUSB0 - FTDI FT232R_USB_UART (SN: A12BC34D)
  2. /dev/ttyUSB1 - Prolific_Technology_Inc USB-Serial Controller
  3. /dev/ttyS0

Select device number [1-3]:
```

**Important**: The devices shown will depend on your specific system and what USB devices are connected. You may see:
- Only one device if you have a single USB serial adapter
- Multiple devices if you have other USB serial devices
- Different device names (/dev/ttyACM0, /dev/ttyAMA0, etc.) depending on the adapter type

**Action required**:
- Carefully identify which device is your RS-485 adapter
- Look for recognizable manufacturer names (FTDI, Prolific, CH340, etc.)
- If unsure, it's usually the most recently connected USB device
- Enter the number corresponding to your RS-485 adapter

**No devices found?** The script will warn you and allow you to skip this step. You can configure the device later, but make sure your RS-485 adapter is properly connected.

#### Phase 4: Device Symlink Creation

The script offers to create a persistent `/dev/ttyHeatPump` symlink using udev rules. This ensures your device is always accessible at the same path, even after reboots.

**What you'll see:**
```
=================================================================
Creating Device Symlink
=================================================================

Create /dev/ttyHeatPump symlink for easy access? [Y/n]: y
ℹ  Creating udev rule: /etc/udev/rules.d/99-waterfurnace-heatpump.rules
ℹ  Reloading udev rules...
✓  Symlink created: /dev/ttyHeatPump -> /dev/ttyUSB0
```

**Action required**:
- Press Enter (or type 'y') to create the symlink (recommended)
- Type 'n' if you prefer to use the device path directly

**Benefits of symlink**:
- Device path remains consistent even if USB devices are reordered
- Easier to remember: `/dev/ttyHeatPump` vs `/dev/ttyUSB0`
- More robust across system changes

#### Phase 5: User Permissions

To access serial devices, your user needs to be in the `dialout` group.

**What you'll see:**
```
=================================================================
Configuring User Permissions
=================================================================

ℹ  To access serial devices, user 'pi' needs to be in the 'dialout' group
Add user 'pi' to the dialout group? [Y/n]: y
✓  User added to dialout group
⚠  You will need to log out and back in for this change to take effect
```

**Action required**:
- Press Enter to add your user to the dialout group

#### Phase 6: Ruby Version Check

The script verifies your Ruby installation is compatible.

**Note**: This step may take a few seconds on slower devices like Raspberry Pi Zero.

**What you'll see:**
```
=================================================================
Checking Ruby Version
=================================================================

ℹ  Found Ruby version: 2.7.4
✓  Ruby version is compatible
```

**If Ruby version is too new** (3.0+), you'll see a warning and can choose to continue anyway.

#### Phase 7: Gem Installation

The script installs the `waterfurnace_aurora` gem and its dependencies from RubyGems.org.

**Note**: This step can take several minutes, especially on slower devices like Raspberry Pi Zero. Some gems require building native extensions which will show "Building native extensions. This could take a while..." - this is normal.

**What you'll see:**
```
=================================================================
Installing WaterFurnace Aurora Gem
=================================================================

ℹ  Installing gems: waterfurnace_aurora
Fetching sinatra-4.2.1.gem
Fetching rack-protection-4.2.1.gem
Fetching rack-3.2.4.gem
...
Successfully installed tilt-2.6.1
Successfully installed rack-3.2.4
Building native extensions. This could take a while...
Successfully installed digest-crc-0.7.0
Building native extensions. This could take a while...
Successfully installed nio4r-2.7.5
Building native extensions. This could take a while...
Successfully installed puma-6.6.1
...
Successfully installed waterfurnace_aurora-1.5.8
19 gems installed
✓  Gems installed successfully
```

**Action required**: None - automatic. Be patient during native extension builds.

#### Phase 8: Gem Testing

The script tests that all installed gems can be loaded correctly.

**What you'll see:**
```
=================================================================
Testing Installed Gems
=================================================================

ℹ  Testing waterfurnace_aurora...
✓  waterfurnace_aurora loaded successfully

✓  All gems are working correctly!
```

**If gems fail to load**: The script will warn you and allow you to continue or abort. This is rare but may indicate compatibility issues.

#### Phase 9: Hardware Communication Test

The script attempts to communicate with your actual heat pump to verify the connection works.

**What you'll see (success)**:
```
=================================================================
Testing Hardware Communication
=================================================================

ℹ  Testing communication with heat pump at /dev/ttyHeatPump...
ℹ  Querying Model Number and Serial Number...

✓  Successfully communicated with heat pump!

Model Number (92): G7AV060BV1A12CTL2D10
Serial Number (105): 252024571

ℹ  Your WaterFurnace Aurora system is responding correctly
```

**What you'll see (failure)**:
```
✗  Failed to communicate with heat pump

Error output:
[error details]

⚠  This could mean:
  • The heat pump is not connected to /dev/ttyHeatPump
  • The RS-485 adapter is not working properly
  • The device permissions are not set correctly
  • The heat pump is powered off

Continue with installation anyway? [Y/n]:
```

**Action required**:
- If successful: No action needed, continue
- If failed:
  - Check your cable connections
  - Verify the heat pump is powered on
  - Ensure you selected the correct serial device
  - You can continue anyway and troubleshoot later

#### Phase 10: MQTT Broker Setup

The script can install and configure Mosquitto MQTT broker for local use.

**What you'll see:**
```
=================================================================
MQTT Broker Setup
=================================================================

ℹ  The WaterFurnace Aurora MQTT bridge requires an MQTT broker

If you're using home automation software, you may already have one:
  • Home Assistant - Includes Mosquitto MQTT Broker add-on
  • OpenHAB - Often uses Mosquitto installed separately
  • Other systems - Many include or support Mosquitto MQTT broker

You can either install Mosquitto locally or point to an existing broker

Would you like to install Mosquitto MQTT broker on this system? [Y/n]:
```

**Action required**: Choose based on your setup:

**Option A: Install Mosquitto locally** (recommended for most users)
- Type 'y' to install Mosquitto on the same device
- You'll be asked about network access configuration:

```
⚠  IMPORTANT: Mosquitto can be configured for different access levels:
ℹ    • Localhost only (127.0.0.1) - Most secure, only local connections
ℹ    • All interfaces (0.0.0.0) - Allows remote connections (less secure)

Configure Mosquitto to listen on localhost only (recommended for security)? [Y/n]:
```

- **Localhost only** (recommended): MQTT is only accessible from the same device
  - Choose this if your home automation software is on the same device
  - More secure - no external network access

- **All interfaces**: MQTT accessible from your local network
  - Choose this if your home automation software is on a different device
  - Less secure - allows unauthenticated network connections

**Option B: Use existing broker**
- Type 'n' if you already have MQTT running elsewhere (like on Home Assistant)
- You'll configure the connection details in the next phase

#### Phase 11: MQTT Bridge Service Setup

The script creates a systemd service to run the MQTT bridge automatically.

**What you'll see:**
```
=================================================================
MQTT Bridge Setup
=================================================================

Would you like to set up the MQTT bridge service? [Y/n]: y
```

Then you'll be prompted for configuration:

```
=================================================================
MQTT Bridge Configuration
=================================================================

Enter MQTT broker hostname [localhost]:
Enter MQTT broker port [1883]:
Enter MQTT username (leave blank if none):
Enter MQTT password:
Enter device name for MQTT [WaterFurnace]:
Enable web aid tool (provides web interface)? [y/N]:
```

**Configuration parameters:**

1. **Serial device path**: Use the default `/dev/ttyHeatPump` if you created the symlink
2. **MQTT broker hostname**:
   - Use `localhost` if Mosquitto is installed locally
   - Use IP address or hostname of your MQTT server if remote
3. **MQTT broker port**: Use default `1883` (standard MQTT port)
4. **MQTT username**: Leave blank if no authentication, or enter your MQTT username
5. **MQTT password**: Only asked if username is provided (password will not be displayed as you type)
6. **Device name**: This appears in MQTT topics as `homie/[device-name]/...`
   - Default is "WaterFurnace"
   - Customize if you have multiple heat pumps
7. **Web aid tool**: Optional web interface (see [Web Aid Tool](#web-aid-tool) section)
   - Type 'y' if you want a web interface
   - Enter port number (default: 4567)
   - Requires downloading HTML assets separately

**Configuration summary** is displayed before creating the service:

```
ℹ  Configuration summary:
  Serial Device: /dev/ttyHeatPump
  MQTT Broker: localhost:1883
  Device Name: WaterFurnace

Enable service to start on boot? [Y/n]: y
✓  Service enabled

Start service now? [Y/n]: y
✓  Service started successfully
```

**Action required**:
- Review the configuration summary
- Confirm to enable the service (recommended)
- Confirm to start the service immediately

**If you need to log out first** (dialout group change):
```
⚠  Cannot start service now - you need to log out and back in first
ℹ  After re-login, start with: sudo systemctl start aurora_mqtt_bridge.service
```

#### Phase 12: Installation Complete

The script displays next steps and useful commands.

**What you'll see:**
```
=================================================================
Installation Complete!
=================================================================

✓  WaterFurnace Aurora has been installed

Next Steps:

  • Check service status:
    sudo systemctl status aurora_mqtt_bridge.service
  • Monitor MQTT messages (using local Mosquitto client):
    mosquitto_sub -h localhost -t 'homie/WaterFurnace/#' -v
  • View service logs:
    sudo journalctl -u aurora_mqtt_bridge.service -f

Command-line Tools:

  • aurora_fetch - Query specific registers
  • aurora_monitor - Monitor ModBus traffic
  • aurora_mock - Simulate ABC for testing
  • aurora_mqtt_bridge - MQTT bridge service

Documentation:

  • Getting Started: GETTING_STARTED.md
  • Hardware Setup: HARDWARE.md
  • Home Assistant: docs/integration/home-assistant.md
  • Troubleshooting: docs/troubleshooting.md
```

## Post-Installation

### Verify the Service is Running

Check the service status:

```bash
sudo systemctl status aurora_mqtt_bridge.service
```

**Expected output:**
```
● aurora_mqtt_bridge.service - WaterFurnace Aurora MQTT Bridge
     Loaded: loaded (/etc/systemd/system/aurora_mqtt_bridge.service; enabled; vendor preset: enabled)
     Active: active (running) since [date/time]
```

If the status shows "failed" or "inactive", check the logs:

```bash
sudo journalctl -u aurora_mqtt_bridge.service -n 50
```

### Monitor MQTT Messages

If you installed Mosquitto locally, you can monitor MQTT messages:

```bash
mosquitto_sub -h localhost -t 'homie/WaterFurnace/#' -v
```

**What you should see:**
```
homie/WaterFurnace/$state ready
homie/WaterFurnace/zone-1/current-temperature 72.5
homie/WaterFurnace/zone-1/target-temperature 70.0
homie/WaterFurnace/heat-pump/entering-water-temperature 45.2
homie/WaterFurnace/heat-pump/total-power-usage 2.3
...
```

### Integrate with Home Automation

#### Home Assistant

1. Configure MQTT integration in Home Assistant:
   - Go to **Settings** → **Devices & Services**
   - Add **MQTT** integration
   - Enter broker details:
     - **Broker**: IP address of your Raspberry Pi (or `localhost` if on same device)
     - **Port**: 1883
     - **Username/Password**: If configured
   - Enable **Enable discovery**

2. WaterFurnace devices will automatically appear in Home Assistant
3. Check **Settings** → **Devices & Services** → **MQTT** for discovered entities

#### OpenHAB

1. Install the [MQTT Binding](https://www.openhab.org/addons/bindings/mqtt/)
2. Add MQTT Broker Thing with your Raspberry Pi's IP address
3. Aurora device will appear automatically in your inbox
4. Accept the discovery and link channels to items

### Web Aid Tool

If you enabled the web aid tool during installation, you need to download the HTML assets:

```bash
cd ~/waterfurnace_aurora
bash contrib/grab_awl_assets.sh
```

If you have an Aurora Web Link, provide its IP address:

```bash
bash contrib/grab_awl_assets.sh 172.20.10.1
```

For older AID tools:
1. Hold the mode button for 5 seconds to enter setup mode
2. LED will flash green rapidly
3. Connect to the `AID-*` WiFi network created by the AID tool
4. Run the script: `bash contrib/grab_awl_assets.sh 192.168.1.1`

Once assets are downloaded, access the web interface at:
```
http://[raspberry-pi-ip]:4567
```

**Note**: For access from other devices, the service must have `APP_ENV=production` set (already configured by the installation script).

## Troubleshooting

### Service Won't Start

**Check logs:**
```bash
sudo journalctl -u aurora_mqtt_bridge.service -n 100
```

**Common issues:**

1. **Permission denied on serial device**
   - Symptom: `Permission denied - /dev/ttyHeatPump`
   - Solution: Log out and log back in (dialout group change requires new login)
   - Verify: `groups` should show `dialout` in the list

2. **Serial device not found**
   - Symptom: `No such file or directory - /dev/ttyHeatPump`
   - Solution: Check if device is connected: `ls -la /dev/ttyUSB*`
   - If device exists but symlink doesn't, reconnect the USB adapter or run: `sudo udevadm trigger`

3. **Cannot connect to MQTT broker**
   - Symptom: `Connection refused` or `MQTT connection failed`
   - Solution: Verify Mosquitto is running: `sudo systemctl status mosquitto`
   - Start if needed: `sudo systemctl start mosquitto`

4. **Working directory permission errors**
   - Symptom: `Failed to access working directory` in logs
   - Solution: Check permissions: `ls -la ~/waterfurnace_aurora`
   - Fix ownership: `sudo chown -R $USER:$USER ~/waterfurnace_aurora`

### Cannot Communicate with Heat Pump

**Test manually:**
```bash
aurora_fetch /dev/ttyHeatPump 2
```

**Expected output:**
```
ABC Program Version (2): 4.03
```

**If it fails:**

1. **Check cable connections**
   - Verify RJ45 jack is firmly seated in AID Tool port
   - Ensure RS-485 wires are properly connected to adapter terminals
   - Check for any damaged wires

2. **Verify correct device**
   ```bash
   ls -la /dev/ttyHeatPump
   ls -la /dev/ttyUSB*
   ```
   Make sure `/dev/ttyHeatPump` points to the correct device

3. **Check device permissions**
   ```bash
   ls -l /dev/ttyHeatPump
   groups
   ```
   You should see `dialout` in groups, and device should be readable

4. **Test with another register**
   ```bash
   aurora_fetch /dev/ttyHeatPump 92-103,105-109
   ```
   This queries model and serial number

5. **Verify heat pump is powered on**
   - The ABC must be powered for communication to work
   - Check that your heat pump control panel is functional

6. **Try different serial device**
   - If you have multiple USB serial devices, try each one
   - Update the service to use the correct device

### MQTT Messages Not Appearing

1. **Verify service is running**
   ```bash
   sudo systemctl status aurora_mqtt_bridge.service
   ```

2. **Check Mosquitto is running**
   ```bash
   sudo systemctl status mosquitto
   ```

3. **Test MQTT connection**
   ```bash
   mosquitto_pub -h localhost -t 'test' -m 'hello'
   mosquitto_sub -h localhost -t 'test'
   ```
   You should see "hello" appear

4. **Check logs for MQTT connection errors**
   ```bash
   sudo journalctl -u aurora_mqtt_bridge.service -f
   ```

### Reconfiguring the Service

If you need to change the MQTT broker, serial device, or other settings:

1. **Run the installation script again**
   ```bash
   ./install.sh
   ```

2. **The script will detect the existing service and offer to reconfigure:**
   - It reads your current configuration
   - Allows you to modify any settings
   - Preserves settings you don't change (just press Enter)

3. **Alternatively, manually edit the service file:**
   ```bash
   sudo nano /etc/systemd/system/aurora_mqtt_bridge.service
   ```

   Then reload and restart:
   ```bash
   sudo systemctl daemon-reload
   sudo systemctl restart aurora_mqtt_bridge.service
   ```

### Uninstalling

To completely remove WaterFurnace Aurora:

```bash
# Stop and disable the service
sudo systemctl stop aurora_mqtt_bridge.service
sudo systemctl disable aurora_mqtt_bridge.service

# Remove service file
sudo rm /etc/systemd/system/aurora_mqtt_bridge.service
sudo systemctl daemon-reload

# Remove udev rule and symlink
sudo rm /etc/udev/rules.d/99-waterfurnace-heatpump.rules
sudo udevadm control --reload-rules
sudo rm /dev/ttyHeatPump

# Remove gem
sudo gem uninstall waterfurnace_aurora

# Remove working directory
rm -rf ~/waterfurnace_aurora

# Optional: Remove MQTT broker if installed
sudo systemctl stop mosquitto
sudo systemctl disable mosquitto
sudo apt remove mosquitto mosquitto-clients
```

## Advanced Configuration

### Using an External MQTT Broker

If you're using an existing MQTT broker (e.g., on Home Assistant):

1. During installation, choose "n" when asked to install Mosquitto
2. When configuring the service, enter your MQTT broker details:
   - Hostname: Your MQTT broker's IP or hostname
   - Port: Usually 1883 (or 8883 for SSL/TLS)
   - Username/Password: If your broker requires authentication

### MQTT over SSL/TLS

To use an encrypted MQTT connection:

1. Configure your MQTT broker to support SSL/TLS
2. When configuring the service, the script currently supports mqtt:// URIs
3. For mqtts:// (SSL/TLS), you'll need to manually edit the service file:
   ```bash
   sudo nano /etc/systemd/system/aurora_mqtt_bridge.service
   ```
   Change `mqtt://` to `mqtts://` in the ExecStart line

### Custom Device Name

The device name appears in MQTT topic paths: `homie/[device-name]/...`

If you have multiple heat pumps, give each a unique name:
- `WaterFurnace-Upstairs`
- `WaterFurnace-Basement`
- `HeatPump-Main`

Configure during installation or reconfigure the service.

### Multiple Heat Pumps

To monitor multiple heat pumps:

1. Connect each heat pump to a different RS-485 adapter
2. Run the installation script for each adapter
3. Configure each with a unique device name
4. Each will need its own systemd service (manually create additional services based on the first)

## Command-Line Tools

The installation provides several command-line utilities:

### aurora_fetch

Query specific registers from your heat pump:

```bash
# Read a single register
aurora_fetch /dev/ttyHeatPump 2

# Read a range of registers
aurora_fetch /dev/ttyHeatPump 745-747

# Read multiple ranges
aurora_fetch /dev/ttyHeatPump 2,745-747,31

# Output as YAML for debugging
aurora_fetch /dev/ttyHeatPump known --yaml > my_heatpump.yml
```

**Special keywords:**
- `known` - All known/documented registers
- `valid` - All registers with valid data
- `all` - All possible registers (slow)

### aurora_monitor

Monitor live ModBus traffic in real-time:

```bash
# Basic monitoring
aurora_monitor /dev/ttyHeatPump

# Quiet mode - only show changes
aurora_monitor /dev/ttyHeatPump -q

# Very quiet - exclude frequently changing values
aurora_monitor /dev/ttyHeatPump -qq
```

Useful for debugging and discovering new registers.

### aurora_mqtt_bridge

Run the MQTT bridge manually (instead of as a service):

```bash
# Basic usage
aurora_mqtt_bridge /dev/ttyHeatPump mqtt://localhost/

# With authentication
aurora_mqtt_bridge /dev/ttyHeatPump mqtt://user:pass@192.168.1.10:1883/

# With custom device name
aurora_mqtt_bridge /dev/ttyHeatPump mqtt://localhost/ --device-name "Basement-HeatPump"

# With web aid tool
aurora_mqtt_bridge /dev/ttyHeatPump mqtt://localhost/ --web-aid-tool=4567

# Access from other devices
APP_ENV=production aurora_mqtt_bridge /dev/ttyHeatPump mqtt://localhost/ --web-aid-tool=4567
```

### aurora_mock

Simulate an ABC for testing (advanced users):

```bash
# Load a YAML dump and serve it to an AID Tool
aurora_mock my_heatpump.yml /dev/ttyHeatPump
```

## Getting Help

If you encounter issues not covered in this guide:

1. **Check the logs:**
   ```bash
   sudo journalctl -u aurora_mqtt_bridge.service -n 100 --no-pager
   ```

2. **Create a diagnostic dump:**
   ```bash
   aurora_fetch /dev/ttyHeatPump valid --yaml > diagnostic_dump.yml
   ```

3. **Visit the GitHub repository:**
   - Issues: https://github.com/ccutrer/waterfurnace_aurora/issues
   - Discussions: https://github.com/ccutrer/waterfurnace_aurora/discussions

4. **Provide diagnostic information:**
   - Your OS version: `cat /etc/os-release`
   - Ruby version: `ruby -v`
   - Service logs: `sudo journalctl -u aurora_mqtt_bridge.service -n 100 --no-pager`
   - Serial device info: `ls -la /dev/ttyUSB* /dev/ttyHeatPump`

## Support the Project

If you find WaterFurnace Aurora helpful, consider supporting the developer:

- **Buy Me a Coffee**: https://buymeacoffee.com/ccutrer
- **Ko-fi**: https://ko-fi.com/ccutrer
- **thanks.dev**: https://thanks.dev/u/gh/ccutrer
- **Venmo**: https://account.venmo.com/u/ccutrer
- **PayPal**: https://paypal.me/ccutrer

Thank you for using WaterFurnace Aurora gem!
