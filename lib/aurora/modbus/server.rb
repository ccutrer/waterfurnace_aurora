module Aurora
  module ModBus
    module Server
      def parse_request(func, req)
        return super unless func == 65
        # 1 function register, a multiple of two words
        return unless (req.length - 1) % 4 == 0
        params = []
        req[1..-1].unpack("n*").each_slice(2) do |(addr, quant)|
          params << { addr: addr, quant: quant }
        end
        params
      end

      def parse_response(func, res)
        func = 3 if func == 65
        super
      end

      def process_func(func, slave, req, params)
        return super unless func == 65
        
        pdu = ""
        params.each do |param|
          if (err = validate_read_func(param, slave.holding_registers))
            return (func | 0x80).chr + err.chr
          end

          pdu += slave.holding_registers[param[:addr],param[:quant]].pack('n*')
        end
        pdu.unshift(pdu.length.chr)
        pdu.unshift(func)
        pdu
      end
    end
  end
end

ModBus::Server::Funcs << 65
