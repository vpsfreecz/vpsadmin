# frozen_string_literal: true

module OutageReportsSpecHelpers
  def with_current_user(user)
    prev = ::User.current
    ::User.current = user
    yield
  ensure
    ::User.current = prev
  end

  def pool_for_node(node)
    return SpecSeed.other_pool if node.id == SpecSeed.other_node.id

    SpecSeed.pool
  end

  def create_dataset_in_pool!(pool:, user: SpecSeed.user)
    dataset = nil

    with_current_user(SpecSeed.admin) do
      dataset = Dataset.create!(
        name: "spec-#{SecureRandom.hex(4)}",
        user: user,
        user_editable: true,
        user_create: true,
        user_destroy: true,
        object_state: :active
      )
    end

    DatasetInPool.create!(dataset: dataset, pool: pool)
  end

  def create_vps!(user:, node:, hostname: nil, os_template: SpecSeed.os_template,
                  dns_resolver: SpecSeed.dns_resolver)
    dataset_in_pool = create_dataset_in_pool!(pool: pool_for_node(node), user: user)

    vps = Vps.new(
      user: user,
      node: node,
      hostname: hostname || "spec-vps-#{SecureRandom.hex(4)}",
      os_template: os_template,
      dns_resolver: dns_resolver,
      dataset_in_pool: dataset_in_pool,
      object_state: :active,
      confirmed: :confirmed
    )

    with_current_user(SpecSeed.admin) do
      vps.save!
    end

    vps
  rescue ActiveRecord::RecordInvalid
    vps.save!(validate: false)
    vps
  end

  def create_export!(user:, pool: SpecSeed.pool, path: nil)
    dip = create_dataset_in_pool!(pool: pool, user: user)
    export = nil

    Uuid.generate_for_new_record! do |uuid|
      export = Export.new(
        dataset_in_pool: dip,
        snapshot_in_pool_clone: nil,
        snapshot_in_pool_clone_n: 0,
        user: user,
        all_vps: false,
        path: path || "/export/#{dip.dataset.full_name}",
        rw: true,
        sync: true,
        subtree_check: false,
        root_squash: false,
        threads: 8,
        enabled: true,
        object_state: :active,
        confirmed: :confirmed
      )
      export.uuid = uuid
      export.save!
      export
    end

    export
  end

  def create_outage_with_translation!(attrs = {}, summary: 'Spec outage', description: 'Spec description')
    outage = nil
    callbacks = ::Outage._initialize_callbacks
    has_callback = callbacks.any? { |cb| cb.filter == :load_translations }

    ::Outage.skip_callback(:initialize, :after, :load_translations) if has_callback
    outage = ::Outage.create!(attrs)
  ensure
    ::Outage.set_callback(:initialize, :after, :load_translations) if has_callback
    if outage
      lang = ::Language.find_by(code: 'en')
      if lang
        ::OutageTranslation.create!(outage: outage, language: lang, summary: summary, description: description)
      end
      outage.reload
    end
  end
end
