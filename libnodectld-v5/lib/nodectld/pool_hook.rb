module NodeCtld
  # Interface for external hook scripts to communicate events to the nodectld
  # daemon.
  module PoolHook
    def self.pre_import(env)
      require_vars!(env, %w[OSCTL_POOL_NAME])

      RemoteClient.send_or_not(RemoteControl::SOCKET, :pool_hook, {
                                 hook_name: :pre_import,
                                 pool: env['OSCTL_POOL_NAME']
                               })
    end

    def self.post_import(env)
      require_vars!(env, %w[OSCTL_POOL_NAME])

      RemoteClient.send_or_not(RemoteControl::SOCKET, :pool_hook, {
                                 hook_name: :post_import,
                                 pool: env['OSCTL_POOL_NAME']
                               })
    end

    def self.pre_export(env)
      require_vars!(env, %w[OSCTL_POOL_NAME])

      RemoteClient.send_or_not(RemoteControl::SOCKET, :pool_hook, {
                                 hook_name: :pre_export,
                                 pool: env['OSCTL_POOL_NAME']
                               })
    end

    def self.require_vars!(env, vars)
      vars.each do |v|
        next if env[v]

        warn 'Expected environment variables:'
        warn "  #{vars.join("\n  ")}"
        warn
        warn "#{v} not found"
        exit(false)
      end
    end
  end
end
