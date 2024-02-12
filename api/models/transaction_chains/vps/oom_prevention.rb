module TransactionChains
  class Vps::OomPrevention < ::TransactionChain
    label 'OOM Prevention'

    # @param vps [::Vps]
    # @param action [:restart, :stop]
    # @param ooms_in_period [Integer]
    # @param period_seconds [Integer]
    # @return [OomPrevention]
    def link_chain(vps:, action:, ooms_in_period:, period_seconds:)
      unless %i[restart stop].include?(action)
        raise ArgumentError, "unknown action #{action.inspect}"
      end

      lock(vps)
      concerns(:affect, [vps.class.name, vps.id])

      mail(:vps_oom_prevention, {
        user: vps.user,
        vars: {
          base_url: ::SysConfig.get(:webui, :base_url),
          vps:,
          action:,
          ooms_in_period:,
          period_seconds:,
        },
      })

      case action
      when :restart
        use_chain(Vps::Restart, args: [vps])
      when :stop
        use_chain(Vps::Stop, args: [vps])
      end

      ::OomPrevention.create!(
        vps:,
        action:
      )
    end
  end
end
