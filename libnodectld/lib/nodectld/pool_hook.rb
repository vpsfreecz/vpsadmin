module NodeCtld
  # Interface for external hook scripts to communicate events to the nodectld
  # daemon.
  module PoolHook
    def self.pre_import(pool)
      RemoteClient.send_or_not(RemoteControl::SOCKET, :pool_hook, {
                                 hook_name: :pre_import,
                                 pool: pool
                               })
    end

    def self.post_import(pool)
      RemoteClient.send_or_not(RemoteControl::SOCKET, :pool_hook, {
                                 hook_name: :post_import,
                                 pool: pool
                               })
    end

    def self.pre_export(pool)
      RemoteClient.send_or_not(RemoteControl::SOCKET, :pool_hook, {
                                 hook_name: :pre_export,
                                 pool: pool
                               })
    end
  end
end
