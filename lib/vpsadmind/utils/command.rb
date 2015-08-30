module VpsAdmind::Utils
  module Command
    module ClassMethods
      # Mapping of module names.
      MODULES = {
          :log => :Log,
          :system => :System,
          :vz => :Vz,
          :zfs => :Zfs,
          :vps => :Vps,
          :worker => :Worker,
          :pool => :Pool,
          :subprocess => :Subprocess,
          :integrity => :Integrity,
          :hypervisor => :Hypervisor,
      }

      # Includes module from VpsAdmind::Utils using mapping
      # in Base::MODULES.
      def needs(*args)
        args.each do |arg|
          if arg.is_a?(Array)
            needs(arg)

          else
            send(:include, VpsAdmind::Utils.const_get(MODULES[arg]))
          end
        end
      end
    end

    def self.included(klass)
      klass.send(:extend, ClassMethods)
    end
  end
end
