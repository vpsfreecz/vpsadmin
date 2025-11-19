module NodeCtld
  class Commands::Vps::CgroupVersion < Commands::Base
    handle 2039
    needs :libvirt, :vps

    def exec
      set_cgroup_version(@new_version)
      ok
    end

    def rollback
      set_cgroup_version(@original_version)
      ok
    end

    protected

    def set_cgroup_version(v)
      set_domain_kernel_parameter(domain, 'vpsadmin.cgroupv', v.to_s)
    end
  end
end
