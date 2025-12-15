module NodeCtld
  class Commands::Vps::DetachIsoImage < Commands::Base
    handle 2042
    needs :libvirt, :vps

    def exec
      return ok unless domain.active?

      update_cdrom(domain, nil)

      ok
    end

    def rollback
      return ok unless domain.active?

      update_cdrom(domain, @iso_image)

      ok
    end
  end
end
