module NodeCtld
  # Interface for external hook scripts to communicate events to the nodectld
  # daemon.
  module CtHook
    def self.pre_start(env)
      require_vars!(env, %w[OSCTL_POOL_NAME OSCTL_CT_ID])
    end

    def self.veth_up(env)
      require_vars!(env, %w[OSCTL_POOL_NAME OSCTL_CT_ID OSCTL_HOST_VETH OSCTL_CT_VETH])

      RemoteClient.send_or_not(RemoteControl::SOCKET, :ct_hook, {
                                 hook_name: :veth_up,
                                 pool: env['OSCTL_POOL_NAME'],
                                 vps_id: env['OSCTL_CT_ID'].to_i,
                                 host_veth: env['OSCTL_HOST_VETH'],
                                 ct_veth: env['OSCTL_CT_VETH']
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
