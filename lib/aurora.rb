# frozen_string_literal: true

require "rmodbus"

require "aurora/abc_client"
require "aurora/mock_abc"
require "aurora/modbus/server"
require "aurora/modbus/slave"
require "aurora/registers"
require "aurora/version"

# extend ModBus for WaterFurnace's custom functions
ModBus::RTUServer.include(Aurora::ModBus::Server)
ModBus::Client::Slave.prepend(Aurora::ModBus::Slave)
ModBus::RTUSlave.prepend(Aurora::ModBus::RTU)

module Aurora
end
