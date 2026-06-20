require_relative 'transaction_chains/security_advisories/mail'

class SecurityAdvisory < ApplicationRecord
  attr_reader :last_chain

  has_many :security_advisory_cves, class_name: 'SecurityAdvisoryCve', dependent: :delete_all
  has_many :security_advisory_translations, dependent: :delete_all
  has_many :security_advisory_node_statuses, dependent: :delete_all
  has_many :nodes, through: :security_advisory_node_statuses
  has_many :security_advisory_vpses, dependent: :delete_all
  has_many :vpses, through: :security_advisory_vpses
  has_many :security_advisory_users, dependent: :delete_all
  has_many :security_advisory_updates, dependent: :destroy
  belongs_to :created_by, class_name: 'User', optional: true
  belongs_to :published_by, class_name: 'User', optional: true

  enum :state, %i[draft published retracted]

  after_initialize :load_translations

  def self.visible_to(user)
    return all if user && user.role == :admin

    where(state: [states[:published], states[:retracted]])
  end

  def self.advisory_nodes
    ::Node.where(
      active: true,
      role: [
        ::Node.roles[:node],
        ::Node.roles[:storage]
      ]
    ).order(:id)
  end

  def self.normalize_cve(cve)
    cve.to_s.strip.upcase
  end

  def self.parse_cves(value)
    value.to_s.split(/[,\s]+/).map { |v| normalize_cve(v) }.reject(&:empty?).uniq
  end

  def cves
    security_advisory_cves.order(:cve_id).pluck(:cve_id).join(', ')
  end

  def cve_urls
    security_advisory_cves.order(:cve_id).map(&:url).join(', ')
  end

  def cve_ids
    security_advisory_cves.order(:cve_id).pluck(:cve_id)
  end

  def affected(user: nil)
    user ||= ::User.current
    return false unless user

    security_advisory_users.where(user_id: user.id).any?
  end

  def affected_node_count
    security_advisory_node_statuses.where(state: ::SecurityAdvisoryNodeStatus.states[:mitigated]).count
  end

  def affected_user_count
    security_advisory_users.count
  end

  def affected_vps_count
    security_advisory_vpses.count
  end

  def update_cves!(value)
    ids = self.class.parse_cves(value)
    if ids.empty?
      errors.add(:cves, 'must contain at least one CVE')
      raise ActiveRecord::RecordInvalid, self
    end

    transaction do
      security_advisory_cves.where.not(cve_id: ids).delete_all

      ids.each do |cve_id|
        security_advisory_cves.find_or_create_by!(cve_id:)
      end
    end
  end

  def update_translations!(translations)
    translations.each do |lang, tr_attrs|
      tr = security_advisory_translations.find_or_initialize_by(language: lang)
      tr.assign_attributes(tr_attrs)
      tr.save!
    end

    load_translations
  end

  def publish!(send_mail: false, published_by: nil, published_at: nil)
    validate_publishable!

    transaction do
      self.state = 'published'
      self.published_at = published_at if published_at
      self.published_at ||= Time.now
      self.published_by = published_by if published_by
      save!
      rebuild_affected!
    end

    mail_chain(:announce) if send_mail
    self
  end

  def retract!(send_mail: false)
    update!(state: 'retracted', retracted_at: Time.now)
    mail_chain(:update) if send_mail
    self
  end

  def rebuild_affected!
    transaction do
      mitigated = security_advisory_node_statuses
                  .where(state: ::SecurityAdvisoryNodeStatus.states[:mitigated])
                  .includes(node: { location: :environment })
                  .to_a
      by_node = mitigated.to_h { |s| [s.node_id, s] }
      active_states = [
        ::Vps.object_states[:active],
        ::Vps.object_states[:suspended]
      ]
      affected = ::Vps.unscoped
                      .includes(node: { location: :environment })
                      .where(node_id: by_node.keys, object_state: active_states)
                      .order(:id)
                      .to_a

      affected.each do |vps|
        ns = by_node.fetch(vps.node_id)
        rec = security_advisory_vpses.find_or_initialize_by(vps:)
        rec.assign_attributes(
          user: vps.user,
          environment: vps.node.location.environment,
          location: vps.node.location,
          node: vps.node,
          node_state: ::SecurityAdvisoryNodeStatus.states[ns.state],
          vulnerable_until: ns.vulnerable_until,
          mitigated_since: ns.mitigated_since
        )
        rec.save!
      end

      security_advisory_vpses.where.not(vps_id: affected.map(&:id)).delete_all
      rebuild_affected_users!
    end
  end

  def rebuild_affected_users!
    user_ids = security_advisory_vpses.distinct.pluck(:user_id)

    user_ids.each do |user_id|
      security_advisory_users.find_or_initialize_by(user_id:).tap do |rec|
        rec.vps_count = security_advisory_vpses.where(user_id:).count
        rec.save!
      end
    end

    security_advisory_users.where.not(user_id: user_ids).delete_all
  end

  def validate_publishable!
    if security_advisory_cves.empty?
      errors.add(:base, 'at least one CVE must be assigned')
    end

    missing = self.class.advisory_nodes.where.not(
      id: security_advisory_node_statuses.select(:node_id)
    )

    if missing.exists?
      errors.add(:base, "missing node status for #{missing.map(&:domain_name).join(', ')}")
    end

    unresolved = security_advisory_node_statuses.where(
      node_id: self.class.advisory_nodes.select(:id),
      state: [
        ::SecurityAdvisoryNodeStatus.states[:unknown],
        ::SecurityAdvisoryNodeStatus.states[:vulnerable]
      ]
    )

    if unresolved.exists?
      errors.add(:base, "unresolved node status for #{unresolved.includes(:node).map { |s| s.node.domain_name }.join(', ')}")
    end

    invalid_mitigated = security_advisory_node_statuses.where(
      state: ::SecurityAdvisoryNodeStatus.states[:mitigated]
    ).where('vulnerable_until IS NULL OR mitigated_since IS NULL')

    errors.add(:base, 'mitigated nodes must have vulnerable_until and mitigated_since') if invalid_mitigated.exists?

    raise ActiveRecord::RecordInvalid, self if errors.any?
  end

  def create_update!(attrs = {}, translations = {}, advisory_attrs: {}, send_mail: false)
    transaction do
      advisory_update = security_advisory_updates.create!(
        attrs.merge(reported_by: ::User.current)
      )

      translations.each do |lang, tr_attrs|
        advisory_update.security_advisory_translations.create!(
          tr_attrs.merge(language: lang)
        )
      end

      update!(advisory_attrs) if advisory_attrs.any?

      if attrs[:state]
        update!(state: attrs[:state])
        update_column(:retracted_at, Time.now) if attrs[:state].to_s == 'retracted'
      end

      advisory_update.load_translations
      mail_chain(:update, update: advisory_update) if send_mail
      advisory_update
    end
  end

  def load_translations
    return if id.nil?

    ::SecurityAdvisoryTranslation.joins(
      'RIGHT JOIN languages ON languages.id = security_advisory_translations.language_id'
    ).where(
      security_advisory_id: id
    ).each do |tr|
      lang = tr.language
      next unless lang

      %i[summary description response].each do |param|
        define_singleton_method("#{lang.code}_#{param}") do
          tr.send(param)
        end
      end
    end
  end

  def mail_chain(event, update: nil)
    @last_chain = nil
    VpsAdmin::API::NotificationEvents.run_chain(
      TransactionChains::SecurityAdvisories::Mail,
      args: [self, event, update]
    )
  end
end
