module NodeCtld
  class Commands::Node::AuthorizeSendKey < Commands::Base
    handle 5262
    needs :system, :osctl

    def exec
      osctl(
        %i(receive authorized-keys add),
        @name,
        {ctid: @ctid, passphrase: @passphrase, single_use: true},
        {pool: pool_name},
        {input: @pubkey},
      )
    end

    def rollback
      osctl(
        %i(receive authorized-keys del),
        @name,
        {},
        {pool: pool_name},
        {valid_rcs: [1,]},
      )
    end

    protected
    def pool_name
      @pool_name ||= @pool_fs.split('/').first
    end
  end
end
