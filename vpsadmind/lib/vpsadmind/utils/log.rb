module VpsAdmind::Utils
  module Log
    module PrivateMethods
      def self.log_time
        Time.new.strftime('%Y-%m-%d %H:%M:%S')
      end

      def self.log(level, type, msg)
        puts "[#{log_time} #{level.to_s.upcase} #{type}] #{msg}"
      end

      def self.cmd_type(cmd)
        "trans=#{cmd.transaction_id},cmd=#{cmd.command_id},type=#{cmd.method}"
      end
    end

    module CommonMethods
      # Arguments are either +level+, +type+, +msg+ or +msg+ only.
      # +level+ defaults info, +type+ to general.
      # If +type+ is a VpsAdmind::Command or VpsAdmind::Commands::Base
      # instance, special behaviour is triggered.
      # Log levels: debug, info, work, important, warn, critical, fatal
      # Types: init, general, regular, special types and possibly more
      def log(*args)
        if args.count == 3
          level, type, msg = args
          type ||= 'general'

          if type.is_a?(VpsAdmind::Command)
            type = PrivateMethods.cmd_type(type)

          elsif type.is_a?(VpsAdmind::Commands::Base)
            type = PrivateMethods.cmd_type(type.instance_variable_get(:@command))
          end

          PrivateMethods.log(level, type, msg)

        elsif args.count == 1
          PrivateMethods.log(:info, :general, args.first)

        else
          fail 'Provide either one or three arguments'
        end
      end
    end

    def self.included(klass)
      klass.send(:include, CommonMethods)
      klass.send(:extend, CommonMethods)
    end
  end
end
