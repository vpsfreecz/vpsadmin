module TransactionChains
  class Vps::Features < ::TransactionChain
    label 'Features'

    # @param vps [::Vps]
    # @param features [Array<::VpsFeature>]
    def link_chain(vps, features)
      lock(vps)
      concerns(:affect, [vps.class.name, vps.id])

      append(Transactions::Vps::Features, args: [vps, features]) do
        data = {}

        features.each do |f|
          n = f.name.to_sym

          edit(f, enabled: f.enabled ? 1 : 0) if f.changed?
          data[f.name] = f.enabled
        end

        just_create(vps.log(:features, data))
      end
    end
  end
end
