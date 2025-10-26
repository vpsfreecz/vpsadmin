require 'erb'
require 'tempfile'
require 'fileutils'
require 'libosctl'
require 'nodectld/utils'

module NodeCtld
  class Vps
    include OsCtl::Lib::Utils::Log
    include Utils::System
    include Utils::Libvirt

    def initialize(domain, cmd: nil)
      @domain = domain
      @vps_id = domain.name
      @cmd = cmd
    end

    def start(autostart_priority: nil)
      @domain.create
    end

    def stop(kill: false, timeout: 300)
      begin
        st, = distconfig(@domain, %W[stop #{kill ? 'kill' : 'stop'} #{timeout}])
      rescue Libvirt::Error => e
        log(:warn, "Error during graceful shutdown of VPS #{@vps_id}: #{e.message} (#{e.class})")
      end

      if st == 0
        60.times do
          return unless @domain.active?

          log(:debug, "Waiting for VPS #{@vps_id} to gracefully shutdown")
          sleep(1)
        end
      end

      begin
        @domain.destroy
      rescue Libvirt::Error
        # pass
      end

      nil
    end

    def restart(autostart_priority: nil)
      stop
      start(autostart_priority:)
    end

    def passwd(user, password)
      distconfig!(@domain, %W[passwd #{user}], input: password)
    end

    def honor_state
      before = @domain.active?
      yield
      after = @domain.active?

      if before && !after
        start
      elsif !before && after
        stop
      end
    end

    def log_type
      if @cmd
        @cmd.log_type
      else
        "vps=#{@vps_id}"
      end
    end
  end
end
