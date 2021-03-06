module Aurora
  module ModBus
    module Slave
      def read_multiple_holding_registers(*ranges)
        values = if ranges.any? { |r| r.is_a?(Range) }
          addrs_and_lengths = ranges.map { |r| r = Array(r); [r.first, r.last - r.first + 1] }.flatten
          query("\x41" + addrs_and_lengths.pack("n*")).unpack("n*")
        else
          query("\x42" + ranges.pack("n*")).unpack("n*")
        end
        ranges.map { |r| Array(r) }.flatten.zip(values).to_h
      end

      def holding_registers
        WFProxy.new(self, :holding_register)
      end
    end

    class WFProxy < ::ModBus::ReadWriteProxy
      def [](*keys)
        return super if keys.length == 1
        @slave.read_multiple_holding_registers(*keys)
      end
    end

    module RTU
      def read_rtu_response(io)
        # Read the slave_id and function code
        msg = read(io, 2)
        log logging_bytes(msg)
  
        function_code = msg.getbyte(1)
        case function_code
          when 1,2,3,4,65,66 then
            # read the third byte to find out how much more
            # we need to read + CRC
            msg += read(io, 1)
            msg += read(io, msg.getbyte(2)+2)
          when 5,6,15,16 then
            # We just read in an additional 6 bytes
            msg += read(io, 6)
          when 22 then
            msg += read(io, 8)
          when 0x80..0xff then
            msg += read(io, 3)
          else
            raise ModBus::Errors::IllegalFunction, "Illegal function: #{function_code}"
        end
      end
    end
  end
end
