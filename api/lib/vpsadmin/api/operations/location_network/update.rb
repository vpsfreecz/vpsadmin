require 'vpsadmin/api/operations/base'

module VpsAdmin::API
  class Operations::LocationNetwork::Update < Operations::Base
    event_policy :resource, models: [::LocationNetwork, ::Network]
    # @param ln [::LocationNetwork]
    # @param opts [Hash]
    # @option opts [Boolean] :primary
    # @option opts [Integer] :priority
    # @option opts [Boolean] :autopick
    # @option opts [Boolean] :userpick
    # @return [::LocationNetwork]
    def run(ln, opts)
      ActiveRecord::Base.transaction do
        if opts.has_key?(:primary)
          if ln.primary && !opts[:primary]
            ln.network.update!(primary_location: nil)
          elsif !ln.primary && opts[:primary]
            previous_primary = ln.network.location_networks
                                 .where(primary: true)
                                 .where.not(id: ln.id)
                                 .to_a
            ::LocationNetwork.where(id: previous_primary.map(&:id))
                             .update_all(primary: nil)
            VpsAdmin::API::Events::ActionPolicies.record_many(
              :updated,
              previous_primary,
              changed_fields: %i[primary]
            )
            ln.network.update!(primary_location: ln.location)
          end
        end

        ln.update!(opts)
        ln
      end
    end
  end
end
