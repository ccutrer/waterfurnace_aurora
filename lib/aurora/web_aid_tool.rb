# frozen_string_literal: true

require "sinatra/base"

module Aurora
  class WebAIDTool < Sinatra::Base
    class << self
      attr_accessor :modbus_slave, :monitor, :units, :mutex
    end

    extend Forwardable
    delegate %i[modbus_slave monitor units units= mutex] => "self.class"

    self.mutex = Mutex.new
    self.units = 0

    set :public_folder, "html"
    set :logging, false
    set :server, "puma"

    get "/" do
      send_file "html/index.htm"
    end

    get "/getunits.cgi" do
      encode_result(units: units)
    end

    get "/setunits.cgi" do
      self.units = params["units"].to_i
      encode_result(error: 0)
    end

    get "/config.cgi" do
      encode_result(
        "AWL Version" => Aurora::VERSION,
        "Local Web Version" => 1.08,
        "SSID" => nil,
        "Units" => units,
        "AWL ID" => ARGV[0],
        "AWL ID CRC" => nil
      )
    end

    get "/request.cgi" do
      params = URI.decode_www_form(request.query_string).to_h
      result = params.slice("cmd", "id", "set", "addr")
      result["err"] = nil

      # these are just aliases to get a certain set of registers
      case params["cmd"]
      when "abcinfo"
        params["regs"] = "2;8;88,4"
      when "devices"
        params["regs"] = "800;803;806,3;812;815;818;824"
      end

      case params["cmd"]
      when "getregs", "abcinfo", "devices"
        queries = params["regs"].split(";").map do |range|
          start, length = range.split(",").map(&:to_i)
          next start if length.nil?

          start...(start + length)
        end
        registers = mutex.synchronize { modbus_slave.read_multiple_holding_registers(*queries) }
        if monitor
          puts "READING"
          puts Aurora.print_registers(registers)
        end
        result["values"] = registers.values.join(",")
      when "putregs"
        writes = params["regs"].split(";").map do |write|
          write.split(",").map(&:to_i)
        end.compact.to_h
        if monitor
          puts "WRITING"
          puts Aurora.print_registers(writes)
        end

        mutex.synchronize do
          writes.each do |(addr, value)|
            modbus_slave.write_holding_register(addr, value)
          end
        end
      else
        return ""
      end

      encode_result(result)
    end

    private

    def parse_query_string(query_string)
      query_string.split("&").map { |p| p.split("=") }.to_h
    end

    # _don't_ do URI escaping
    def encode_result(params)
      params.map { |p| p.join("=") }.join("&")
    end
  end
end
