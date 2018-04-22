require 'libosctl'

module NodeCtld::Utils
  module Command
    module ClassMethods
      # Mapping of module names.
      MODULES = {
        system: :System,
        osctl: :OsCtl,
        zfs: :Zfs,
        vps: :Vps,
        worker: :Worker,
        pool: :Pool,
        subprocess: :Subprocess,
        integrity: :Integrity,
        hypervisor: :Hypervisor,
        outage_window: :OutageWindow,
        queue: :Queue,
      }

      # Includes module from NodeCtld::Utils using mapping
      # in Base::MODULES.
      def needs(*args)
        args.each do |arg|
          if arg.is_a?(Array)
            needs(arg)

          elsif arg == :log
            send(:include, ::OsCtl::Lib::Utils::Log)

          else
            send(:include, NodeCtld::Utils.const_get(MODULES[arg]))
          end
        end
      end
    end

    def self.included(klass)
      klass.send(:extend, ClassMethods)
    end
  end
end
