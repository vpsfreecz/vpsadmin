module VpsAdmind
  class Commands::Vps::Features < Commands::Base
    handle 8001
    needs :system, :vz, :vps

    def exec
      set_features('enabled')
    end

    def rollback
      set_features('original')
    end

    protected
    def set_features(key)
      honor_state do
        vzctl(:stop, @vps_id)
        
        opts = {
            :feature => [],
            :capability => [],
            :netfilter => 'stateless',
            :numiptent => '1000',
            :devices => []
        }

        if @features['iptables'][key]
          opts[:netfilter] = 'full'
        end

        if @features['nfs'][key]
          opts[:feature] << 'nfsd:on' << 'nfs:on'
        end

        if @features['tun'][key]
          opts[:capability] << 'net_admin:on'
          opts[:devices] << 'c:10:200:rw'
        end

        if @features['fuse'][key]
          opts[:devices] << 'c:10:229:rw'
        end

        if @features['ppp'][key]
          opts[:feature] << 'ppp:on'
          opts[:devices] << 'c:108:0:rw'
        end

        vzctl(:set, @vps_id, opts, true)

        vzctl(:start, @vps_id)
        sleep(3)

        if @features['tun'][key]
          vzctl(:exec, @vps_id, 'mkdir -p /dev/net')
          vzctl(:exec, @vps_id, 'mknod /dev/net/tun c 10 200', false, [8,])
          vzctl(:exec, @vps_id, 'chmod 600 /dev/net/tun')
        end

        if @features['fuse'][key]
          vzctl(:exec, @vps_id, 'mknod /dev/fuse c 10 229', false, [8,])
        end

        if @features['ppp'][key]
          vzctl(:exec, @vps_id, 'mknod /dev/ppp c 108 0', false, [8,])
          vzctl(:exec, @vps_id, 'chmod 600 /dev/ppp')
        end
      end

      ok
    end
  end
end
