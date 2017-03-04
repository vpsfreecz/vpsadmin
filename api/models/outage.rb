class Outage < ActiveRecord::Base
  has_many :outage_entities
  has_many :outage_handlers
  has_many :outage_updates
  has_many :outage_translations
  has_many :outage_vpses
  has_many :vpses, through: :outage_vpses

  enum state: %i(staged announced closed cancelled)
  enum outage_type: %i(tbd restart reset network performance maintenance)

  after_initialize :load_translations

  # TODO: pick a different method name?
  def self.create!(attrs, translations = {})
    transaction do
      outage = new(attrs)
      outage.save!

      attrs.delete(:planned)

      report = ::OutageUpdate.new(attrs)
      report.outage = outage
      report.state = 'staged'
      report.reported_by = ::User.current
      report.save!

      translations.each do |lang, attrs|
        tr = ::OutageTranslation.new(attrs)
        tr.language = lang
        tr.outage = outage
        tr.save!
      end

      outage.save!
      outage.load_translations
      outage
    end
  end

  # TODO: pick a different method name?
  def update!(attrs = {}, translations = {}, opts = {})
    VpsAdmin::API::Plugins::OutageReports::TransactionChains::Update.fire(
        self,
        attrs,
        translations,
        opts
    )
  end

  # TODO: check that we have outage entities, handlers and description
  def announce!(opts = {})
    update!({state: self.class.states[:announced]}, {}, opts)
  end

  def close!(opts = {})
    update!({state: self.class.states[:closed]}, {}, opts)
  end

  def cancel!(opts = {})
    update!({state: self.class.states[:cancelled]}, {}, opts)
  end

  def load_translations
    outage_translations.each do |tr|
      %i(summary description).each do |param|
        define_singleton_method("#{tr.language.code}_#{param}") do
          tr.send(param)
        end
      end
    end
  end

  # @return [Boolean] true if the current user is affected by this outage
  def affected
    return false if ::User.current.nil? || state != 'announced'
    return false if finished_at && finished_at < Time.now

    vpses.where(user: ::User.current).count > 0
  end

  def affected_users
    ::User.joins(vpses: [:outage_vpses]).where(
        outage_vpses: {outage_id: self.id}
    ).group('outage_vpses.outage_id, users.id').order('users.id')
  end

  def affected_user_count
    affected_users.count.size
  end

  def affected_vps_count
    outage_vpses.count
  end

  def get_affected_vpses
    q = []

    outage_entities.each do |ent|
      id = self.class.connection.quote(ent.row_id)
      state = self.class.connection.quote(::User.object_states[:hard_delete])

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

    q.empty? ? [] : ::Vps.find_by_sql(<<-END
      SELECT * FROM (
        #{q.join("\nUNION\n")}
      ) as tmp
      GROUP BY tmp.id
      ORDER BY tmp.id
      END
    )
  end

  # Store affected VPSes in model {OutageVps}
  def set_affected_vpses
    self.class.transaction do
      affected = get_affected_vpses

      # Register new VPSes
      affected.each do |vps|
        begin
          ::OutageVps.find_by!(outage: self, vps: vps)

        rescue ActiveRecord::RecordNotFound
          ::OutageVps.create!(outage: self, vps: vps)
        end
      end

      # Delete no longer affected VPSes (if affected entities change)
      ::OutageVps.where(outage: self).each do |outage_vps|
        exists = affected.detect { |v| v.id == outage_vps.vps_id }
        next if exists

        outage_vps.destroy!
      end
    end
  end

  def to_hash
    ret = {
        id: id,
        planned: planned,
        begins_at: begins_at.iso8601,
        duration: duration,
        type: outage_type,
        entities: outage_entities.map { |v| {name: v.name, id: v.row_id, label: v.real_name} },
        handlers: outage_handlers.map { |v| v.full_name },
        translations: {},
    }

    outage_translations.each do |tr|
      ret[:translations][tr.language.code] = {
          summary: tr.summary,
          description: tr.description,
      }
    end

    ret
  end
end
