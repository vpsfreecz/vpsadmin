require 'singleton'

module NodeCtld
  class NbdAllocator
    include Singleton

    class << self
      %i[get_device free_device].each do |m|
        define_method(m) do |*args, **kwargs, &block|
          instance.send(m, *args, **kwargs, &block)
        end
      end
    end

    def initialize
      @devices = Dir.glob('/dev/nbd*')

      if @devices.empty?
        raise 'No nbd devices detected, ensure nbd module is loaded'
      end

      @free_devices = @devices.clone
      @mutex = Mutex.new
      @cv = ConditionVariable.new
    end

    # @return [String]
    def get_device
      @mutex.synchronize do
        return @free_devices.shift if @free_devices.any?

        @cv.wait(@mutex)
        raise 'Programming error: expected a free device' if @free_devices.empty?

        @free_devices.shift
      end
    end

    # @param device [String]
    def free_device(device)
      unless @devices.include?(device)
        raise ArgumentError, "Unknown device #{device.inspect}, must be one of #{@devices.join(', ')}"
      end

      @mutex.synchronize do
        signal = @free_devices.empty?

        @free_devices << device
        @free_devices.uniq!
        @free_devices.sort!

        @cv.signal if signal
      end

      nil
    end
  end
end
