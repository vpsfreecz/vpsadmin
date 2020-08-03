require 'vpsadmin/api/operations/base'

module VpsAdmin::API
  class Operations::LocationNetwork::Update < Operations::Base
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
            ln.network.update!(primary_location: ln.location)
          end
        end

        ln.update!(opts)
      end
    end
  end
end
