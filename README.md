# WaterFurnace Aurora Gem

This gem is a Ruby library for interacting directly with Aurora-based
WaterFurnace heat pump systems. It connects directly to the RS-485
communication bus that the AID Tool Aurora Web Link (AWL)/Symphony
systems use. WaterFurnace provides zero documentation on this protocol,
besides to occasionally mention in their manual that it is standards
based ModBus (spoiler alert - it is, but only in the loosest sense).
It is ModBus in that is based on a series of registers that can be read
and/or written, and even by standard ModBus commands, but the
WaterFurnace tools (AID Tool and AWL) use proprietary extensions to
ModBus in order to address a large number of registers at once.

This gem relies on the RModBus gem for basic ModBus communication,
but the WaterFurnace specific extensions live in this repository.
The register map has been deciphered in a number of ways:
 * capturing traffic between an AID Tool and the ABC (Aurora Base
   Control)
 * capturing traffic between an AWL and the ABC
 * capturing traffic between an AID tool and this code,
   masquerading as an ABC.

Note that as of now, this code and register map has _only_ been tested
against a WaterFurnace 7-series residential unit, coupled with an
IntelliZone 2 zone controller hosting 6 zones. It's highly likely that
different units (like a 3 or 5 series) or thermostat configurations
(single thermostat, IntelliZone 1) will use different registers, and
as such will not be able to expose some of the most useful information,
such as the current temperature, set point, and requested mode of the
thermostat. If you own a different unit, I would be glad to have your
helping extending support!

|Make|Model|Working|
--- | --- | ---
|Waterfurnace|7-series|Yes|
|Geosmart|PremiumV|Yes|

## Installation

Install ruby 2.6 or 2.7. 3.0 has not been tested. If talking directly
to the serial port, Linux is required. Mac may or may not work. Windows
probably won't work. If you want to run on Windows, you'll need to run
a network serial port (like with `ser2net`), and connect remotely from
the Windows machine. Then:

```sh
gem install waterfurnace_aurora 
```
On Ubuntu 21.04 the following is needed to install the gem:

```sh
sudo apt install build-essential ruby2.7 ruby-dev
```

## MQTT/Homie Bridge

An MQTT bridge is provided to allow easy integration into other systems. You
will need a separate MQTT server running ([Mosquitto](https://mosquitto.org) is
a relatively easy and robust one). The MQTT topics follow the [Homie
convention](https://homieiot.github.io), making them self-describing. If you're
using a systemd Linux distribution, an example unit file is provided in
`contrib/aurora_mqtt_bridge.service`. So a full example would be (once you have
Ruby installed):

```sh
sudo curl https://github.com/ccutrer/waterfurnace_aurora/raw/main/contrib/aurora_mqtt_bridge.service -L -o /etc/systemd/system/aurora_mqtt_bridge.service
<modify the file to pass the correct URI to your MQTT server, and path to RS-485 device>
<If you use MQTT authentication you can use the following format to provide login information mqtt://username:password@mqtt.domain.tld >
<Make sure to change the "User" and "WorkingDirectory" parameters to fit your environnement>
sudo systemctl enable aurora_mqtt_bridge
sudo systemctl start aurora_mqtt_bridge
```

Once connected, status updates such as current temperature, set point, and a
plethora of other diagnostic information, will be published to MQTT regularly.
Several properties such as set point and current mode can also be written
back to the ABC via MQTT.

### ModBus Pass Through

The MQTT bridge has pass through support for direct querying and writing of the
ModBus registers, to assist with debugging. If you send a register, or list of
registers, to the `$modbus` topic, it will read those registers and send them
back. You can also write to a register by addressing `$modbus/:register/set`:

```
813 => homie/aurora-<serialno>/$modbus
homie/aurora-<serialno>/$modbus/813 <= IZ2 Version (813): 2.06

745-747 => homie/aurora-<serialno>/$modbus
homie/aurora-<serialno>/$modbus/745 <= Heating Set Point (745): 68.0ºF
homie/aurora-<serialno>/$modbus/746 <= Cooling Set Point (746): 73.0ºF
homie/aurora-<serialno>/$modbus/747 <= Ambient Temperature (747): 73.0ºF

known => homie/aurora-<serialno>/$modbus
<a whole ton of data sent back!>

valid => homie/aurora-<serialno>/$modbus
<even more data!>

3 => homie/aurora-<serialno>/$modbus/340/set
homie/aurora-<serialno>/$modbus/340 <= Blower Only Speed (340): 3
```

## Connecting to the ABC

This gem supports using an RS-485 direct connection. It is possible to directly
connect to the GPIO on a Raspberry Pi, or to use a USB RS-485 dongle such as
[this one from Amazon](https://www.amazon.com/gp/product/B07B416CPK).
The key is identifying the correct wires as RS-485+ and RS-485-. It's easiest
to take an existing ethernet cable, and cut off one end. Connect pins 1 and 3
(white/orange and white/green for a TIA-568-B configured cable) to + and pins
2 and 4 (orange and green) -. The other pins are C and R from the thermostat
bus, providing 24VAC power. DO NOT SHORT THESE PINS AGAINST ANYTHING, such
as the communication pins, or a ground connection anywhere. Best case scenario
you blow a 5A automotive fuse in your heat pump that you will need to replace.
Worst case scenario you completely brick your ABC board. You have been warned,
and I am not liable for any problems attempting to do this. Once your cable is
built, connect to the AID Tool port on the front of your heat pump, and then
your RS-485 device on your computer.

![Bus Connection](doc/connection_chart.png)

When using a TIA-568-B terminated cable with a USB RS-485 dongle the connections should be the following:

|Dongle terminal |RJ-45 Pin |Wire color |RS-485|
--- | --- | --- | --- 
|TXD+|1 and 3|white-orange and white-green |A+|
|TXD-|2 and 4|solid orange and solid blue |B-|
|RXD+|None|None|None|
|RXD-|None|None|None|
|GND |None|None|None|

### Connection with AWL

If you would still like your AWL to function, you can connect AWL to the AID
port, and then connect your computer to the AID pass-through port on the AWL.

### Non-local Serial Ports

Serial ports over the network are also supported. Just give a URI like
tcp://192.168.1.10:2000/ instead of a local device. Be sure to set up your
server (like ser2net) to use 19200 baud, EVEN. You can also use RFC2217 serial
ports (allowing the serial connection parameters to be set automatically) with
a URI like telnet://192.168.1.10:2217/.

### Connecting _between_ the ABC and another device

If you need to eavesdrop over existing communication, it is possible to 
mangle an ethernet cable such that it still has both ends, but you're connected
in the middle. But I find it much easier to use an RJ45 breakout board such as
[this one from Amazon](https://www.amazon.com/gp/product/B01GNOBDPM). You
connect a cable from the heat pump to the board, one from the board to your
RS-485 dongle, and one from the board to the AWL or AID Tool. If you're
simulating the ABC, you would omit the cable to the heat pump. But the AID Tool
still needs power, so you can either build an additional cable as above, but
this time breaking out C and R, and connecting to a 24VAC power supply. Or you
can just connect directly to the terminals on the breakout board without
building a special cable. The cable has the advantage of being able to quickly
re-configure by only switching cable connections, rather than screwing or
unscrewing terminals.

## Deciphering Additional Registers

### aurora_monitor

This tool simply monitors all traffic on the serial bus, and dumps out anything
it can decipher. This includes raw register values for registers that are not
recognized. This is used when you are connected between an AID Tool or AWL and
the ABC. Trigger an action on the AID Tool or the Symphony website, watch the
dump, and guess what's what! It has several options (see `--help`) tweak its
output, but the most useful is `-q` which combines several of them to only
print when registers actually change, and exclude known, frequently updating
values (like power usage sensors):

```
$ aurora_monitor /dev/ttyHeatPump -q
2021-08-27 14:05:15 +0000 ===== read
Last Fault Number (25): E0
Last Lockout (26): E19
System Outputs (At Last Lockout) (27): blower, accessory, 0x0040
System Inputs (At Last Lockout) (28): Y1, G, 0x0180
System Outputs (30): rv, blower, accessory, 0x0040
Status (31): {:lps=>:closed, :hps=>:closed, :unknown=>"0x0018"}
??? (35): 1 (0x0001)
??? (73): 682 (0x02aa)
??? (74): 715 (0x02cb)
??? (320): 0 (0x0000)
??? (324): 99 (0x0063)
ECM Speed (344): 2
??? (348): 10 (0x000a)
DHW Setpoint (401): 130.0ºF
Relative Humidity (741): 51%
??? (742): 0 (0x0000)
??? (743): 0 (0x0000)
??? (744): 24 (0x0018)
Heating Set Point (745): 74.0ºF
Cooling Set Point (746): 72.0ºF
Ambient Temperature (747): 0.0ºF
...
```

### aurora_mock

This tool masquerades as an ABC. To date, I've only used this against an AID
tool, and not an AWL, in order to not confuse WaterFurnace's servers with
potentially bogus data. You modify bin/registers.yml to pre-set the data,
and then it serves it up when the AID Tool requests it. Change some date, go
look in the AID tool what changed, to see if you guessed right!

### aurora_fetch

This tool simply queries a specific set of registers, and prints the results.
This is used when you are connected to the AID Tool port (either of the
heat pump itself, or the AWL). It accepts the same syntax as
[the MQTT ModBus pass through](#modbus-pass-through):

```
$ aurora_fetch /dev/ttyHeatPump 745-746
Heating Set Point (745): 68.0ºF
Cooling Set Point (746): 73.0ºF

$ aurora_fetch /dev/ttyHeatPump 745-746 --yaml
---
745: 680
746: 730
```

### web_aid_tool

This is a reproduction of the web AID tool, as provided on some early AWL
units. It depends on code from an actual AWL. For copyright reasons, these
files are not provided. You will need to download them from your AWL, and
place them into an html directory:

 * indexfd49.html
 * js/indexc.js
 * css/index.css
 * images/aurora.png
 * images/back.png
 * images/cfailed.png
 * images/cgood.png
 * images/cidle.png

Then run the web AID tool:

```
$ web_aid_tool /dev/ttyHeatPump
```

After which you'll be able top open a browser to http://localhost:4567/.
