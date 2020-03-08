module NodeCtld
  class PoolAuthorizedKeys
    include OsCtl::Lib::Utils::Log
    include Utils::System
    include Utils::OsCtl

    attr_reader :pool

    # @param pool [String]
    def initialize(pool)
      @pool = pool
      @keys = {}
      reload
    end

    # @param pubkey [String]
    # @param reload [Boolean]
    def authorize(pubkey, reload: true)
      return if keys.has_value?(pubkey)

      osctl(
        %i(receive authorized-keys add),
        [], {}, {pool: pool}, {input: pubkey}
      )
      self.reload if reload
    end

    # @param pubkey [String]
    def revoke(pubkey)
      index = keys.key(pubkey)

      if index
        osctl(%i(receive authorized-keys del), [index], {}, {pool: pool})
        reload
      end
    end

    protected
    attr_reader :keys

    def reload
      keys.clear

      osctl_parse(%i(receive authorized-keys ls), [], {}, {pool: pool}).each do |key|
        keys[key[:index]] = key[:key]
      end
    end
  end
end
