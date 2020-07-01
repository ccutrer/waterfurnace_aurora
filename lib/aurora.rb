require 'rmodbus'

require 'aurora/modbus/server'
require 'aurora/modbus/slave'
require 'aurora/registers'

# extend ModBus for WaterFurnace's custom functions
ModBus::RTUServer.include(Aurora::ModBus::Server)
ModBus::Client::Slave.prepend(Aurora::ModBus::Slave)
ModBus::RTUSlave.prepend(Aurora::ModBus::RTU)

module Aurora
end
