module NodeCtld
  class Commands::Pool::AuthorizeSendKey < Commands::Base
    handle 5262
    needs :system, :osctl

    def exec
      osctl_pool(
        @pool_name,
        %i(receive authorized-keys add),
        @name,
        {ctid: @ctid, passphrase: @passphrase, single_use: true},
        {},
        {input: @pubkey},
      )
    end

    def rollback
      osctl_pool(
        @pool_name,
        %i(receive authorized-keys del),
        @name,
        {},
        {},
        {valid_rcs: [1,]},
      )
    end
  end
end
