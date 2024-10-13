require 'vpsadmin/api/operations/base'

module VpsAdmin::API
  class Operations::Vps::SetFeatures < Operations::Base
    # @param vps [::Vps]
    # @param features [Hash<Symbol, Boolean>]
    # @return [::TransactionChain]
    def run(vps, features)
      chain, = TransactionChains::Vps::Features.fire(vps, build_features(vps, features))
      chain
    end

    protected

    # @return [Array<::VpsFeature>]
    def build_features(vps, features)
      set = vps.vps_features.map do |f|
        n = f.name.to_sym
        f.enabled = features[n] if features.has_key?(n)
        f
      end

      # Check for conflicts
      set.each do |f1|
        set.each do |f2|
          raise VpsAdmin::API::Exceptions::VpsFeatureConflict.new(f1, f2) if f1.conflict?(f2)
        end
      end

      set
    end
  end
end
