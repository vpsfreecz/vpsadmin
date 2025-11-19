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

    def initialize(domain, vps_config: nil, cmd: nil)
      @domain = domain
      @vps_id = domain.name
      @vps_config = vps_config || VpsConfig.read(@vps_id)
      @cmd = cmd
    end

    def start(autostart_priority: nil)
      @domain.create
    end

    def stop(kill: false, timeout: 300)
      if @vps_config.vm_type == 'qemu_container'
        stop_qemu_container(kill:, timeout:)
      else
        stop_qemu_full(kill:, timeout:)
      end
    end

    def restart(autostart_priority: nil)
      stop
      start(autostart_priority:)
    end

    def passwd(user, password)
      if @vps_config.vm_type == 'qemu_container'
        distconfig!(@domain, %W[passwd #{user}], input: password, run: true)
      else
        @domain.qemu_agent_command({
          'execute' => 'guest-set-user-password',
          'arguments' => {
            'username' => user,
            'password' => password
          }
        }.to_json)
      end
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

    protected

    def stop_qemu_container(kill:, timeout:)
      begin
        st, = distconfig(@domain, ['stop', kill ? 'kill' : 'stop', timeout])
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

    def stop_qemu_full(kill:, timeout:)
      if kill
        @domain.destroy
        return
      end

      begin
        @domain.shutdown(Libvirt::Domain::SHUTDOWN_GUEST_AGENT)
      rescue Libvirt::Error => e
        log(:warn, "Unable to shutdown VPS #{@vps_id} using guest agent: #{e.message} (#{e.class})")
      end

      timeout.times do
        return unless @domain.active?

        log(:debug, "Waiting for VPS #{@vps_id} to gracefully shutdown")
        sleep(1)
      end

      begin
        @domain.destroy
      rescue Libvirt::Error
        # pass
      end

      nil
    end
  end
end
