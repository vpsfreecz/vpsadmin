module NodeCtld
  class Commands::Vps::DeployPublicKey < Commands::Base
    handle 2017
    needs :system, :libvirt, :vps

    def exec
      distconfig!(domain, %w[authorized-key-add], input: @pubkey, run: true)
      ok
    end

    def rollback
      distconfig!(domain, %w[authorized-key-del], input: @pubkey, run: true)
      ok
    end
  end
end
