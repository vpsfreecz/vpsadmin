module DistConfig
  module Helpers::Log
    def log(level, message)
      print =
        case level
        when :warn, :fatal
          true
        when :info, :debug
          @verbose
        else
          raise "Unknown log level #{level.inspect}"
        end

      return unless print

      warn "[#{level}] #{message}"
    end
  end
end
