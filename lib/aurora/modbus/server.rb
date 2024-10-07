# frozen_string_literal: true

module Aurora
  module ModBus
    module Server
      def parse_request(func, req)
        case func
        when 65
          # 1 function register, a multiple of two words
          return unless ((req.length - 1) % 4).zero?

          params = []
          req[1..-1].unpack("n*").each_slice(2) do |(addr, quant)|
            params << { addr: addr, quant: quant }
          end
          params
        when 66
          return unless ((req.length - 1) % 2).zero?

          req[1..-1].unpack("n*")
        when 67
          # 1 function register, a multiple of two words
          return unless ((req.length - 1) % 4).zero?

          params = []
          req[1..-1].unpack("n*").each_slice(2) do |(addr, val)|
            params << { addr: addr, val: val }
          end
          params
        when 68
          return unless req.length == 5

          { noidea1: req[1, 2].unpack("n"), noidea2: req[3, 2].unpack("n") }
        else
          super
        end
      end

      def parse_response(func, res)
        return {} if func == 67 && res.length == 1
        return { noidea: res[-1].ord } if func == 68 && res.length == 2

        func = 3 if [65, 66].include?(func)
        super
      end

      def process_func(func, slave, req, params)
        case func
        when 65
          pdu = ""
          params.each do |param|
            if (err = validate_read_func(param, slave.holding_registers))
              return (func | 0x80).chr + err.chr
            end

            pdu += slave.holding_registers[param[:addr], param[:quant]].pack("n*")
          end
          func.chr + pdu.length.chr + pdu

        when 66
          pdu = params.map { |addr| slave.holding_registers[addr] }.pack("n*")
          func.chr + pdu.length.chr + pdu

        when 67
          slave.holding_registers[param[:addr]] = param[:val]
          pdu = req[0, 2]
        else
          super
        end
      end
    end
  end
end

# 65 => read multiple discontiguous register ranges (command is a list of pairs of addr and quant)
# 66 => read multiple discontiguous registers (command is a list of addrs)
# 67 => write multiple discontiguous registers (command is a list of pairs of addr and value; response has no content)
# 68 => ?? request has 4 bytes, response has 1 byte that seems to be 0 (for success?)
funcs = ModBus::Server::FUNCS.dup
funcs.push(65, 66, 67, 68)
ModBus::Server.send(:remove_const, :FUNCS)
ModBus::Server.const_set(:FUNCS, funcs.freeze)
