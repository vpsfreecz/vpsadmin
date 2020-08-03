require 'vpsadmin/api/operations/base'

module VpsAdmin::API
  class Operations::LocationNetwork::Create < Operations::Base
    # @param opts [Hash]
    # @option opts [::Location] :location
    # @option opts [::Network] :network
    # @option opts [Boolean] :primary
    # @option opts [Integer] :priority
    # @option opts [Boolean] :autopick
    # @option opts [Boolean] :userpick
    # @return [::LocationNetwork]
    def run(opts)
      ActiveRecord::Base.transaction do
        ln = ::LocationNetwork.create!(opts)
        ln.network.update!(primary_location: ln.location) if ln.primary
        ln
      end
    end
  end
end
