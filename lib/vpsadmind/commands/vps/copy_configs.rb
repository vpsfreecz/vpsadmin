module VpsAdmind
  class Commands::Vps::CopyConfigs < Commands::Base
    handle 4001
    needs :system, :vz, :vps

    CONFIGS = [:mount, :umount, :conf]

    def exec
      if @local
        files.each do |src, dst|
          next unless File.exists?(src)

          syscmd("#{$CFG.get(:bin, :cp)} -p #{src} #{dst}")
        end
        
        check_config!

        if @vps_id != @dst_vps
            vzctl(:set, @dst_vps, {
                :root => ve_root(@dst_vps),
                :private => ve_private(@dst_vps)
            }, true)
        end

      else
        files.each do |src, dst|
          # Accept return code 1 - file not found
          scp("#{@src_node_addr}:#{src}", "#{dst}", nil, [1])
        end
        
        check_config!
      end

      vzctl(:set, @dst_vps, {:onboot => 'no'}, true)
    end

    def rollback
      files.each do |src, dst|
        next unless File.exists?(dst)

        syscmd("#{$CFG.get(:bin, :mv)} #{dst} #{dst}.destroyed")
      end

      ok
    end

    protected
    def files
      ret = {}
      
      CONFIGS.each do |suffix|
        ret["#{$CFG.get(:vz, :vz_conf)}/conf/#{@vps_id}.#{suffix}"] = \
            "#{$CFG.get(:vz, :vz_conf)}/conf/#{@dst_vps}.#{suffix}"
      end

      ret[File.join($CFG.get(:vpsadmin, :mounts_dir), "#{@vps_id}.mounts")] = \
          File.join($CFG.get(:vpsadmin, :mounts_dir), "#{@dst_vps}.mounts")

      ret
    end

    def check_config!
      unless File.exists?("#{$CFG.get(:vz, :vz_conf)}/conf/#{@dst_vps}.conf")
        fail 'CT config does not exist'
      end
    end
  end
end
