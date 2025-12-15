module NodeCtld
  class Commands::Vps::AttachIsoImage < Commands::Base
    handle 2041
    needs :libvirt, :vps

    def exec
      return ok unless domain.active?

      update_cdrom(domain, @new_iso_image)

      ok
    end

    def rollback
      return ok unless domain.active?

      update_cdrom(domain, @original_iso_image)

      ok
    end
  end
end
