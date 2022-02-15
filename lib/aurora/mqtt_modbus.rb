# frozen_string_literal: true

require "mqtt"
require "securerandom"

module Aurora
  class MQTTModBus
    attr_accessor :logger

    def initialize(uri)
      @mqtt = MQTT::Client.new(uri)
      @mqtt.connect

      @base_topic = uri.path[1..-1]
      @mqtt.subscribe("#{@base_topic}/getregs/response")
    end

    def read_multiple_holding_registers(*queries)
      query_id = SecureRandom.uuid
      mqtt_query = queries.map { |m| m.is_a?(Range) ? "#{m.begin},#{m.count}" : m }.join(";")
      @mqtt.publish("#{@base_topic}/getregs", "#{query_id}:#{mqtt_query}", qos: 1)
      Timeout.timeout(5) do
        result = {}
        loop do
          packet = @mqtt.get
          response_id, registers_flat = packet.payload.split(":")
          next unless response_id == query_id

          values = registers_flat.split(",").map(&:to_i)
          result_index = 0
          queries.each do |query|
            Array(query).each do |i|
              result[i] = values[result_index]
              result_index += 1
            end
          end
          break
        end
        result
      end
    end

    def write_holding_register(addr, value)
      @mqtt.publish("#{@base_topic}/#{addr}/set", value, qos: 1)
    end
  end
end
