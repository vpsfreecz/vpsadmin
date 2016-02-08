module TransactionChains
  class Vps::Features < ::TransactionChain
    label 'Features'

    def link_chain(vps, features)
      lock(vps)
      concerns(:affect, [vps.class.name, vps.id])

      append(Transactions::Vps::Features, args: [vps, features]) do
        data = {}

        vps.vps_features.each do |f|
          n = f.name.to_sym

          edit(f, enabled: features[n] ? 1 : 0) if !features[n].nil? && f.enabled != features[n]
          data[f.name] = features[n].nil? ? f.enabled : features[n]
        end

        just_create(vps.log(:features, data))
      end
    end
  end
end
