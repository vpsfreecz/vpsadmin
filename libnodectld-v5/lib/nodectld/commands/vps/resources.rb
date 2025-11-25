module NodeCtld
  class Commands::Vps::Resources < Commands::Base
    handle 2003
    needs :system, :libvirt, :vps

    def exec
      set('value')
      ok
    end

    def rollback
      set('original')
      ok
    end

    protected

    def set(key)
      @resources.each do |r|
        case r['resource']
        when 'cpu_limit'
          vcpu_period = $CFG.get(:libvirt, :cpu_period)

          # NOTE: while there's ruby API Libvirt::Domain.scheduler_parameters=, it simply
          # does not work for vcpu_quota -- it always complains about the value being out
          # of range.
          # See https://gitlab.com/libvirt/libvirt-ruby/-/issues/15
          if r[key] && r[key] > 1000
            syscmd("virsh schedinfo #{@vps_uuid} --set vcpu_period=#{vcpu_period} vcpu_quota=#{r[key] / 100 * vcpu_period}")
          else
            syscmd("virsh schedinfo #{@vps_uuid} --set vcpu_period=#{vcpu_period} vcpu_quota=-1")
          end
        end
      end
    end
  end
end
