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

      prevention = ::OomPrevention.create!(
        vps:,
        action:
      )

      event = prepare_event!(
        'vps.oom_prevention',
        user: vps.user,
        vps:,
        source: prevention,
        subject: "OOM prevention for VPS ##{vps.id}",
        summary: "vpsAdmin will #{action} VPS ##{vps.id} after #{ooms_in_period} OOM events",
        payload: {
          action: action.to_s,
          reason: 'repeated out-of-memory events',
          ooms_in_period:,
          period_seconds:
        }
      )

      case action
      when :restart
        use_chain(Vps::Restart, args: [vps])
      when :stop
        use_chain(Vps::Stop, args: [vps])
      end

      release_event_deliveries!(event)

      prevention
    end
  end
end
