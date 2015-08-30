module TransactionChains
  class VpsConfig::Update < ::TransactionChain
    label 'Update'

    def link_chain(cfg)
      lock(cfg)
      concerns(:affect, [cfg.class.name, cfg.id])

      if cfg.changed == %w(label)
        cfg.save!
        return cfg
      end

      ::Node.where(server_type: 'node').each do |n|
        append(Transactions::Hypervisor::UpdateConfig, args: [n, cfg])
      end

      changes = {}
      changes[:name] = cfg.name if cfg.name_changed?
      changes[:label] = cfg.label if cfg.label_changed?
      changes[:config] = cfg.config if cfg.config_changed?

      append(Transactions::Utils::NoOp, args: find_node_id) do
        edit(cfg, changes)
      end unless changes.empty?

      cfg
    end
  end
end
