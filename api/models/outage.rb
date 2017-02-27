class Outage < ActiveRecord::Base
  has_many :outage_entities
  has_many :outage_handlers
  has_many :outage_updates
  has_many :outage_translations
  
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
  def update!(attrs = {}, translations = {})
    VpsAdmin::API::Plugins::OutageReports::TransactionChains::Update.fire(
        self,
        attrs,
        translations
    )
  end

  # TODO: check that we have outage entities, handlers and description
  def announce!
    update!(state: self.class.states[:announced])
  end

  def close!
    update!(state: self.class.states[:closed])
  end

  def cancel!
    update!(state: self.class.states[:cancelled])
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

    affected_vpses(::User.current).count > 0
  end

  # @return [Array<User>] list of users that are affected by this outage
  def affected_users
    q = []

    outage_entities.each do |ent|
      id = self.class.connection.quote(ent.row_id)
      state = self.class.connection.quote(::User.object_states[:hard_delete])

      case ent.name
      when 'Cluster'
        q.clear
        q << <<-END
          SELECT * FROM users
          WHERE object_state < #{state}
        END
        break

      when 'Environment'
        q << <<-END
          SELECT u.* FROM users u
          INNER JOIN vpses v ON u.id = v.user_id
          INNER JOIN nodes n ON v.node_id = n.id
          INNER JOIN locations l ON l.id = n.location_id
          WHERE
            l.environment_id = #{id}
            AND u.object_state < #{state}
            AND v.object_state < #{state}
        END

      when 'Location'
        q << <<-END
          SELECT u.* FROM users u
          INNER JOIN vpses v ON u.id = v.user_id
          INNER JOIN nodes n ON v.node_id = n.id
          WHERE
            n.location_id = #{id}
            AND u.object_state < #{state}
            AND v.object_state < #{state}
        END

      when 'Node'
        q << <<-END
          SELECT u.* FROM users u
          INNER JOIN vpses v ON u.id = v.user_id
          WHERE
            v.node_id = #{id}
            AND u.object_state < #{state}
            AND v.object_state < #{state}
        END
      end
    end

    q.empty? ? [] : ::User.find_by_sql(<<-END
      SELECT * FROM (
        #{q.join("\nUNION\n")}
      ) as tmp
      GROUP BY tmp.id
      ORDER BY tmp.id
      END
    )
  end

  def affected_vpses(user)
    q = []

    outage_entities.each do |ent|
      uid = self.class.connection.quote(user.id)
      id = self.class.connection.quote(ent.row_id)
      state = self.class.connection.quote(::User.object_states[:hard_delete])

      case ent.name
      when 'Cluster'
        q.clear
        q << <<-END
          SELECT * FROM vpses
          WHERE object_state < #{state} AND user_id = #{uid}
        END
        break

      when 'Environment'
        q << <<-END
          SELECT v.* FROM vpses v
          INNER JOIN nodes n ON v.node_id = n.id
          INNER JOIN locations l ON l.id = n.location_id
          WHERE
            v.user_id = #{uid}
            AND l.environment_id = #{id}
            AND v.object_state < #{state}
        END

      when 'Location'
        q << <<-END
          SELECT v.* FROM vpses v
          INNER JOIN nodes n ON v.node_id = n.id
          WHERE
            v.user_id = #{uid}
            AND n.location_id = #{id}
            AND v.object_state < #{state}
        END

      when 'Node'
        q << <<-END
          SELECT v.* FROM vpses v
          WHERE
            v.user_id = #{uid}
            AND v.node_id = #{id}
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

  def entity_names
    outage_entities.map do |ent|
      case ent.name
      when 'Cluster'
        'cluster-wide'

      when 'Environment'
        ::Environment.find(ent.row_id).label

      when 'Location'
        ::Location.find(ent.row_id).label

      when 'Node'
        ::Node.find(ent.row_id).domain_name
      end
    end
  end
end
