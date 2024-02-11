require 'erb'
require 'tempfile'
require 'fileutils'
require 'libosctl'
require 'nodectld/utils'

module NodeCtld
  class Vps
    START_TIMEOUT = 'infinity'

    include OsCtl::Lib::Utils::Log
    include Utils::System
    include Utils::OsCtl
    include Utils::Zfs

    def initialize(veid, cmd = nil)
      @veid = veid
      @cmd = cmd
    end

    def start(start_timeout, autostart_priority)
      osctl(%i[ct start], @veid, { wait: start_timeout || START_TIMEOUT })
      osctl(%i[ct set autostart], @veid, { priority: autostart_priority })
    end

    def stop(_params = {})
      osctl(%i[ct stop], @veid)
      osctl(%i[ct unset autostart], @veid)
    end

    def restart(start_timeout, autostart_priority)
      osctl(%i[ct restart], @veid, { wait: start_timeout || START_TIMEOUT })
      osctl(%i[ct set autostart], @veid, { priority: autostart_priority })
    end

    def passwd(user, password)
      osctl(%i[ct passwd], [@veid, user, password])
    end

    def load_file(file)
      vzctl(:exec, @veid, "cat #{file}")
    end

    def status
      osctl_parse(%i[ct show], @veid)[:state].to_sym
    end

    def honor_state
      before = status
      yield
      after = status

      if before == :running && after != :running
        start

      elsif before != :running && after == :running
        stop
      end
    end

    def log_type
      if @cmd
        @cmd.log_type
      else
        "vps=#{@veid}"
      end
    end
  end
end
