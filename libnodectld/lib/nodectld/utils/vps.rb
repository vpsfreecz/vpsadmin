module NodeCtld
  module Utils::Vps
    def find_ct(vps_id = nil)
      Ct.new(osctl_parse(%i(ct show), vps_id || @vps_id))
    end

    def ct
      @ct || (@ct = find_ct)
    end

    def status
      find_ct.state
    end

    def honor_state
      before = status
      yield
      after = status

      if before == :running && after != :running
        call_cmd(Commands::Vps::Start, {vps_id: @vps_id})

      elsif before != :running && after == :running
        call_cmd(Commands::Vps::Stop, {vps_id: @vps_id})
      end
    end

    def ct_hook_dir(pool_fs: @pool_fs, vps_id: @vps_id)
      File.join('/', pool_fs, '..', 'hook/ct', vps_id.to_s)
    end
  end
end
