module VpsAdmind
  class Commands::Vps::CopyConfigs < Commands::Base
    handle 4001
    needs :system, :vz, :vps

    CONFIGS = [:mount, :umount, :conf]

    def exec
      if @local
        CONFIGS.each do |suffix|
          cfg = "#{$CFG.get(:vz, :vz_conf)}/conf/#{@vps_id}.#{suffix}"

          if File.exists?(cfg)
            syscmd("#{$CFG.get(:bin, :cp)} -p #{cfg} #{$CFG.get(:vz, :vz_conf)}/conf/#{@dst_vps}.#{suffix}")
          end
        end

        if @vps_id != @dst_vps
            vzctl(:set, @dst_vps, {:root => ve_root(@dst_vps), :private => ve_private(@dst_vps)})
        end

      else
        CONFIGS.each do |suffix|
          # Accept return code 1 - file not found
          scp(
              "#{@src_node_addr}:#{$CFG.get(:vz, :vz_conf)}/conf/#{@vps_id}.#{suffix}", "#{$CFG.get(:vz, :vz_conf)}/conf/#{@dst_vps}.#{suffix}",
              [suffix != :conf ? 1 : 0]
          )
        end
      end

      vzctl(:set, @dst_vps, {:onboot => 'no'}, true)
    end

    def rollback
      Dir.glob("#{$CFG.get(:vz, :vz_conf)}/conf/#{@dst_vps}.{#{CONFIGS.join(',')}").each do |cfg|
        syscmd("#{$CFG.get(:bin, :mv)} #{cfg} #{cfg}.destroyed")
      end

      ok
    end
  end
end
