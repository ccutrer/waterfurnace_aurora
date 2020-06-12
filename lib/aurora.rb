require 'rmodbus'

require 'aurora/modbus/server'
require 'aurora/registers'

# extend ModBus for WaterFurnace's custom function
ModBus::RTUServer.include(Aurora::ModBus::Server)

module Aurora
end
