module NodeCtld
  class Commands::Vps::Features < Commands::Base
    handle 8001
    needs :system, :osctl, :vps

    def exec
      set_features('enabled')
    end

    def rollback
      set_features('original')
    end

    protected
    def set_features(key)
      # TODO features
      # tun: net_admin capability?
      # bridge: ?
      # nfs: ?

      devices = {
        tun: [%w(char 10 200), '/dev/net/tun'],
        fuse: [%w(char 10 229), '/dev/fuse'],
        ppp: [%w(char 108 0), '/dev/ppp'],
        kvm: [%w(char 10 232), '/dev/kvm'],
      }

      devices.each do |name, desc|
        ident, devnode = desc

        if @features[name.to_s][key]
          # Enable
          osctl(
            %i(ct devices add),
            [@vps_id, *ident, 'rwm', devnode],
            parents: true
          )

        else
          # Disable
          osctl(
            %i(ct devices del),
            [@vps_id, *ident],
            {},
            {},
            valid_rcs: [1]
          )
        end
      end

      ok
    end
  end
end
