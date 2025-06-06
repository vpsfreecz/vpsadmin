class Outage < ApplicationRecord
  has_many :outage_entities
  has_many :outage_handlers
  has_many :outage_updates
  has_many :outage_translations
  has_many :outage_users
  has_many :outage_vpses
  has_many :vpses, through: :outage_vpses
  has_many :outage_exports
  has_many :exports, through: :outage_exports

  enum :state, %i[staged announced resolved cancelled]
  enum :outage_type, %i[maintenance outage]
  enum :impact_type, %i[
    tbd
    system_restart
    system_reset
    network
    performance
    unavailability
    export
  ]

  after_initialize :load_translations

  def self.create_outage!(attrs, translations = {})
    transaction do
      outage = new(attrs)
      outage.save!

      attrs.delete(:outage_type)
      attrs.delete(:auto_resolve)

      report = ::OutageUpdate.new(attrs)
      report.outage = outage
      report.state = 'staged'
      report.reported_by = ::User.current
      report.save!

      translations.each do |lang, tr_attrs|
        tr = ::OutageTranslation.new(tr_attrs)
        tr.language = lang
        tr.outage = outage
        tr.save!
      end

      outage.save!
      outage.load_translations
      outage
    end
  end

  def update_outage!(attrs = {}, translations = {}, _opts = {})
    transaction do
      assign_attributes(attrs)
      save!

      translations.each do |lang, tr_attrs|
        tr = ::OutageTranslation.find_by(
          outage: self,
          language: lang
        )

        if tr.nil?
          tr = ::OutageTranslation.new(tr_attrs)
          tr.language = lang
          tr.outage = self
          tr.save!
        else
          tr.update!(tr_attrs)
        end
      end

      load_translations
      self
    end
  end

  def create_outage_update!(attrs = {}, translations = {}, opts = {})
    attrs[:state] = ::Outage.states[attrs[:state]] if attrs[:state]

    VpsAdmin::API::Plugins::OutageReports::TransactionChains::Update.fire(
      self,
      attrs,
      translations,
      opts
    )
  end

  def do_auto_resolve
    attrs = { state: ::Outage.states['resolved'] }

    attrs[:finished_at] = begins_at + (duration * 60) if finished_at.nil?

    VpsAdmin::API::Plugins::OutageReports::TransactionChains::Update.fire(
      self,
      attrs,
      {},
      { send_mail: false }
    )
  end

  def load_translations
    ::OutageTranslation.joins(
      'RIGHT JOIN languages ON languages.id = outage_translations.language_id'
    ).where(
      outage_id: id
    ).each do |tr|
      %i[summary description].each do |param|
        define_singleton_method("#{tr.language.code}_#{param}") do
          tr.send(param)
        end
      end
    end
  end

  # @param user [::User, nil]
  # @return [Boolean] true if the current user is affected by this outage
  def affected(user: nil)
    user ||= ::User.current

    if user
      outage_users.where(user_id: user.id).any?
    else
      false
    end
  end

  def get_affected_users
    if outage_entities.where(name: 'vpsAdmin').any?
      return ::User
             .where('object_state < ?', ::User.object_states[:soft_delete])
             .order('id')
    end

    users = []
    users.concat(outage_vpses.pluck(:user_id))
    users.concat(outage_exports.pluck(:user_id))
    users.uniq!

    ::User
      .where('object_state < ?', ::User.object_states[:soft_delete])
      .where(id: users)
      .order('id')
  end

  def set_affected_users
    users = get_affected_users

    users.each do |user|
      vps_cnt = outage_vpses.where(user:).count
      export_cnt = outage_exports.where(user:).count

      begin
        outage_users.find_by!(user:).update!(
          vps_count: vps_cnt,
          export_count: export_cnt
        )
      rescue ActiveRecord::RecordNotFound
        outage_users.create!(
          user:,
          vps_count: vps_cnt,
          export_count: export_cnt
        )
      end
    end

    outage_users.where.not(user_id: users.map(&:id)).delete_all
  end

  def affected_user_count
    outage_users.count
  end

  def affected_direct_vps_count
    outage_vpses.where(direct: true).count
  end

  def affected_indirect_vps_count
    outage_vpses.where(direct: false).count
  end

  def affected_export_count
    outage_exports.count
  end

  def get_affected_vpses
    q = []

    outage_entities.each do |ent|
      id = self.class.connection.quote(ent.row_id)
      state = self.class.connection.quote(::Vps.object_states[:soft_delete])

      case ent.name
      when 'Cluster'
        q.clear
        q << <<-END
          SELECT * FROM vpses
          WHERE object_state < #{state}
        END
        break

      when 'Environment'
        q << <<-END
          SELECT v.* FROM vpses v
          INNER JOIN nodes n ON v.node_id = n.id
          INNER JOIN locations l ON l.id = n.location_id
          WHERE
            l.environment_id = #{id}
            AND v.object_state < #{state}
        END

      when 'Location'
        q << <<-END
          SELECT v.* FROM vpses v
          INNER JOIN nodes n ON v.node_id = n.id
          WHERE
            n.location_id = #{id}
            AND v.object_state < #{state}
        END

      when 'Node'
        q << <<-END
          SELECT v.* FROM vpses v
          WHERE
            v.node_id = #{id}
            AND v.object_state < #{state}
        END
      end
    end

    if q.empty?
      []
    else
      ::Vps.find_by_sql(<<-END
      SELECT * FROM (
        #{q.join("\nUNION\n")}
      ) as tmp
      GROUP BY tmp.id
      ORDER BY tmp.id
      END
                       )
    end
  end

  # Store affected VPSes in model {OutageVps}
  def set_affected_vpses
    self.class.transaction do
      affected = get_affected_vpses
      registered_vpses = {}

      # Register new VPSes
      affected.each do |vps|
        begin
          out = ::OutageVps.find_by!(outage: self, vps:).update!(
            user: vps.user,
            environment: vps.node.location.environment,
            location: vps.node.location,
            node: vps.node,
            direct: true
          )
        rescue ActiveRecord::RecordNotFound
          out = ::OutageVps.create!(
            outage: self,
            vps:,
            user: vps.user,
            environment: vps.node.location.environment,
            location: vps.node.location,
            node: vps.node,
            direct: true
          )
        end

        registered_vpses[vps.id] = out
      end

      # Delete no longer affected VPSes (if affected entities change)
      ::OutageVps.where(outage: self).each do |outage_vps|
        exists = affected.detect { |v| v.id == outage_vps.vps_id }
        next if exists

        outage_vps.destroy!
      end
    end
  end

  def get_affected_exports
    q = []

    outage_entities.each do |ent|
      id = self.class.connection.quote(ent.row_id)

      case ent.name
      when 'Cluster'
        q.clear
        q << <<-END
          SELECT * FROM exports
        END
        break

      when 'Environment'
        q << <<-END
          SELECT e.* FROM exports e
          INNER JOIN dataset_in_pools dip ON e.dataset_in_pool_id = dip.id
          INNER JOIN pools p ON dip.pool_id = p.id
          INNER JOIN nodes n ON p.node_id = n.id
          INNER JOIN locations l ON l.id = n.location_id
          WHERE
            l.environment_id = #{id}
        END

      when 'Location'
        q << <<-END
          SELECT e.* FROM exports e
          INNER JOIN dataset_in_pools dip ON e.dataset_in_pool_id = dip.id
          INNER JOIN pools p ON dip.pool_id = p.id
          INNER JOIN nodes n ON p.node_id = n.id
          WHERE
            n.location_id = #{id}
        END

      when 'Node'
        q << <<-END
          SELECT e.* FROM exports e
          INNER JOIN dataset_in_pools dip ON e.dataset_in_pool_id = dip.id
          INNER JOIN pools p ON dip.pool_id = p.id
          WHERE
            p.node_id = #{id}
        END
      end
    end

    if q.empty?
      []
    else
      ::Export.find_by_sql(<<-END
      SELECT * FROM (
        #{q.join("\nUNION\n")}
      ) as tmp
      GROUP BY tmp.id
      ORDER BY tmp.id
      END
                          )
    end
  end

  # Store affected exports in model {OutageExport}
  def set_affected_exports
    self.class.transaction do
      affected = get_affected_exports
      registered_exports = {}

      # Register new exports
      affected.each do |ex|
        node = ex.dataset_in_pool.pool.node

        begin
          out = ::OutageExport.find_by!(outage: self, export: ex).update!(
            user: ex.user,
            environment: node.location.environment,
            location: node.location,
            node:
          )
        rescue ActiveRecord::RecordNotFound
          out = ::OutageExport.create!(
            outage: self,
            export: ex,
            user: ex.user,
            environment: node.location.environment,
            location: node.location,
            node:
          )
        end

        registered_exports[ex.id] = out
      end

      # Delete no longer affected VPSes (if affected entities change)
      ::OutageExport.where(outage: self).each do |outage_export|
        exists = affected.detect { |ex| ex.id == outage_export.export_id }
        next if exists

        outage_export.destroy!
      end
    end
  end

  def to_hash
    ret = {
      id:,
      type: outage_type,
      begins_at: begins_at.iso8601,
      duration:,
      impact: impact_type,
      entities: outage_entities.map { |v| { name: v.name, id: v.row_id, label: v.real_name } },
      handlers: outage_handlers.map(&:full_name),
      translations: {}
    }

    outage_translations.each do |tr|
      ret[:translations][tr.language.code] = {
        summary: tr.summary,
        description: tr.description
      }
    end

    ret
  end
end
