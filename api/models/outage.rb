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

  def close!(translations = {}, opts = {})
    update!({state: self.class.states[:closed]}, translations, opts)
  end

  def cancel!(translations = {}, opts = {})
    update!({state: self.class.states[:cancelled]}, translations, opts)
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
    vpses.where(user: ::User.current).count > 0
  end

  def affected_users
    ::User.joins(vpses: [:outage_vpses]).where(
        outage_vpses: {outage_id: self.id},
    ).where(
        'users.object_state < ?', ::User.object_states[:soft_delete]
    ).group('outage_vpses.outage_id, users.id').order('users.id')
  end

  def affected_user_count
    affected_users.count.size
  end

  def affected_direct_vps_count
    outage_vpses.where(direct: true).count
  end

  def affected_indirect_vps_count
    outage_vpses.where(direct: false).count
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

    q.empty? ? [] : ::Vps.find_by_sql(<<-END
      SELECT * FROM (
        #{q.join("\nUNION\n")}
      ) as tmp
      GROUP BY tmp.id
      ORDER BY tmp.id
      END
    )
  end

  # @param direct_vps [Array<Integer>]
  def get_affected_mounts(direct_vpses)
    q = []
    exclude = direct_vpses.map { |v| self.class.connection.quote(v) }.join(',')
    exclude = '0' if exclude.empty?

    outage_entities.each do |ent|
      id = self.class.connection.quote(ent.row_id)
      state = self.class.connection.quote(::Vps.object_states[:soft_delete])

      case ent.name
      when 'Cluster'
        # All VPS are affected directly anyway
        return []

      when 'Environment'
        q << <<-END
          SELECT m.* FROM mounts m
          INNER JOIN dataset_in_pools dips ON m.dataset_in_pool_id = dips.id
          INNER JOIN pools p ON dips.pool_id = p.id
          INNER JOIN nodes n ON p.node_id = n.id
          INNER JOIN locations l ON n.location_id = l.id
          INNER JOIN vpses v ON m.vps_id = v.id
          WHERE
            v.object_state < #{state}
            AND l.environment_id = #{id}
            AND v.id NOT IN (#{exclude})
        END

      when 'Location'
        q << <<-END
          SELECT m.* FROM mounts m
          INNER JOIN dataset_in_pools dips ON m.dataset_in_pool_id = dips.id
          INNER JOIN pools p ON dips.pool_id = p.id
          INNER JOIN nodes n ON p.node_id = n.id
          INNER JOIN vpses v ON m.vps_id = v.id
          WHERE
            v.object_state < #{state}
            AND n.location_id = #{id}
            AND v.id NOT IN (#{exclude})
        END

      when 'Node'
        q << <<-END
          SELECT m.* FROM mounts m
          INNER JOIN dataset_in_pools dips ON m.dataset_in_pool_id = dips.id
          INNER JOIN pools p ON dips.pool_id = p.id
          INNER JOIN vpses v ON m.vps_id = v.id
          WHERE
            v.object_state < #{state}
            AND p.node_id = #{id}
            AND v.id NOT IN (#{exclude})
        END
      end
    end

    q.empty? ? [] : ::Mount.find_by_sql(<<-END
      SELECT * FROM (
        #{q.join("\nUNION\n")}
      ) as tmp
      GROUP BY tmp.id
      END
    )
  end

  # Store affected VPSes in model {OutageVps}
  def set_affected_vpses
    self.class.transaction do
      affected = get_affected_vpses
      registered_vpses = {}

      # Register new VPSes
      affected.each do |vps|
        begin
          out = ::OutageVps.find_by!(outage: self, vps: vps).update!(
              user: vps.user,
              environment: vps.node.location.environment,
              location: vps.node.location,
              node: vps.node,
              direct: true,
          )

        rescue ActiveRecord::RecordNotFound
          out = ::OutageVps.create!(
              outage: self,
              vps: vps,
              user: vps.user,
              environment: vps.node.location.environment,
              location: vps.node.location,
              node: vps.node,
              direct: true,
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

      # Register indirectly affected VPS (through mounts)
      affected_mounts = get_affected_mounts(registered_vpses.keys)

      affected_mounts.each do |mnt|
        if registered_vpses[mnt.vps_id]
          if registered_vpses[mnt.vps_id].direct
            registered_vpses[mnt.vps_id].update!(direct: false)
          end

        else
          registered_vpses[mnt.vps_id] = ::OutageVps.create!(
              outage: self,
              vps: mnt.vps,
              user: mnt.vps.user,
              environment: mnt.vps.node.location.environment,
              location: mnt.vps.node.location,
              node: mnt.vps.node,
              direct: false,
          )
        end

        begin
          ::OutageVpsMount.find_by!(
              outage_vps: registered_vpses[mnt.vps_id],
              mount: mnt,
          ).update!(
              src_node_id: mnt.dataset_in_pool.pool.node_id,
              src_pool_id: mnt.dataset_in_pool.pool_id,
              src_dataset_id: mnt.dataset_in_pool.dataset_id,
              src_snapshot_id: mnt.snapshot_in_pool && mnt.snapshot_in_pool.dataset_in_pool.dataset_id,
              dataset_name: mnt.dataset_in_pool.dataset.full_name,
              snapshot_name: mnt.snapshot_in_pool && mnt.snapshot_in_pool.snapshot.name,
              mountpoint: mnt.dst,
          )

        rescue ActiveRecord::RecordNotFound
          ::OutageVpsMount.create!(
              outage_vps: registered_vpses[mnt.vps_id],
              mount: mnt,
              src_node_id: mnt.dataset_in_pool.pool.node_id,
              src_pool_id: mnt.dataset_in_pool.pool_id,
              src_dataset_id: mnt.dataset_in_pool.dataset_id,
              src_snapshot_id: mnt.snapshot_in_pool && mnt.snapshot_in_pool.dataset_in_pool.dataset_id,
              dataset_name: mnt.dataset_in_pool.dataset.full_name,
              snapshot_name: mnt.snapshot_in_pool && mnt.snapshot_in_pool.snapshot.name,
              mountpoint: mnt.dst,
          )
        end
      end

      # Delete no longer affected mounts
      ::OutageVpsMount.joins(:outage_vps).where(
          outage_vpses: {outage_id: self.id},
      ).each do |outage_mnt|
        exists = affected_mounts.detect { |v| v.id == outage_mnt.mount_id }
        next if exists

        outage_mnt.destroy!
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
