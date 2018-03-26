module NodeCtld
  module Utils::Vps
    def ve_root(vps_id = nil)
      "#{$CFG.get(:vz, :vz_root)}/root/#{vps_id || @vps_id}"
    end

    def ve_private(vps_id = nil)
      $CFG.get(:vz, :ve_private).gsub(/%\{veid\}/, (vps_id || @vps_id).to_s)
    end

    def ve_conf
      "#{$CFG.get(:vz, :vz_conf)}/conf/#{@vps_id}.conf"
    end

    def status
      stat = vzctl(:status, @vps_id)[:output].split(" ")[2..-1]
      {
          exists: stat[0] == 'exist',
          mounted: stat[1] == 'mounted',
          running: stat[2] == 'running'
      }
    end

    def honor_state
      before = status
      yield
      after = status

      if before[:running] && !after[:running]
        call_cmd(Commands::Vps::Start, {vps_id: @vps_id})

      elsif !before[:running] && after[:running]
        call_cmd(Commands::Vps::Stop, {vps_id: @vps_id})
      end
    end
  end
end
