require_relative 'transaction_chains/security_advisories/mail'

class SecurityAdvisory < ApplicationRecord
  class DraftRequired < StandardError; end
  class ContentEditRequired < StandardError; end
  class RevisionMismatch < StandardError; end
  class StateMismatch < StandardError; end

  attr_reader :last_chain

  has_many :security_advisory_cves, class_name: 'SecurityAdvisoryCve', dependent: :delete_all
  has_many :security_advisory_translations, dependent: :delete_all
  has_many :security_advisory_node_statuses, dependent: :destroy
  has_many :nodes, through: :security_advisory_node_statuses
  has_many :security_advisory_vpses, dependent: :delete_all
  has_many :vpses, through: :security_advisory_vpses
  has_many :security_advisory_users, dependent: :delete_all
  has_many :security_advisory_updates, dependent: :destroy
  belongs_to :created_by, class_name: 'User', optional: true
  belongs_to :published_by, class_name: 'User', optional: true

  enum :state, %i[draft published retracted]

  validates :external_id, length: { maximum: 255 }, uniqueness: true, allow_nil: true

  after_initialize :load_translations

  def self.visible_to(user)
    return all if user && user.role == :admin

    where(state: states[:published])
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

  def mutate_draft!(expected_content_revision: nil)
    with_lock do
      unless draft?
        raise DraftRequired, 'security advisory can only be changed while it is a draft'
      end

      check_content_revision!(expected_content_revision) unless expected_content_revision.nil?

      result = yield
      update_columns(content_revision: content_revision + 1, updated_at: Time.current)
      result
    end
  end

  def update_content!(attrs, translations = {}, expected_content_revision:, expected_state: nil)
    mutate_content!(expected_content_revision:, expected_state:) do
      update!(attrs)
      update_translations!(translations)
      self
    end
  end

  def update_node_status!(status_id, attrs, translations = {}, expected_content_revision:, expected_state: nil)
    mutate_content!(expected_content_revision:, expected_state:) do
      status = security_advisory_node_statuses.lock.find(status_id)
      save_node_status!(status, attrs, translations)
      status
    end
  end

  def create_node_status!(attrs, translations = {}, expected_content_revision:, expected_state: nil)
    mutate_content!(expected_content_revision:, expected_state:) do
      status = security_advisory_node_statuses.build
      save_node_status!(status, attrs, translations)
      status
    end
  end

  def delete_node_status!(status_id, expected_content_revision:, expected_state: nil)
    mutate_content!(expected_content_revision:, expected_state:) do
      security_advisory_node_statuses.lock.find(status_id).destroy!
      rebuild_affected! unless draft?
    end
  end

  def mutate_content!(expected_content_revision:, expected_state: nil)
    # A caller can rescue inside an outer transaction; keep this edit atomic.
    with_lock(requires_new: true) do
      check_content_preconditions!(expected_content_revision:, expected_state:)
      result = yield
      update_columns(content_revision: content_revision + 1, updated_at: Time.current)
      result
    end
  end

  def destroy_content!(expected_content_revision:, expected_state: nil)
    with_lock(requires_new: true) do
      check_content_preconditions!(expected_content_revision:, expected_state:)
      destroy!
    end
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
      tr = security_advisory_translations.lock.find_or_initialize_by(language: lang)
      tr.assign_attributes(tr_attrs)
      tr.save!
    end

    load_translations
  end

  def publish!(expected_content_revision:, send_mail: false, published_by: nil, published_at: nil)
    with_lock(requires_new: true) do
      raise DraftRequired, 'only draft security advisories can be published' unless draft?

      check_content_revision!(expected_content_revision)
      validate_publishable!
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

  def retract!(expected_content_revision:, expected_state: nil)
    mutate_content!(expected_content_revision:, expected_state:) do
      raise ContentEditRequired, 'only published security advisories can be retracted' unless published?

      update!(state: :retracted, retracted_at: Time.current)
      self
    end
  end

  def rebuild_affected!
    with_lock(requires_new: true) do
      # Locking reads also see committed changes inside an older outer transaction.
      mitigated = security_advisory_node_statuses
                  .where(state: ::SecurityAdvisoryNodeStatus.states[:mitigated])
                  .eager_load(node: { location: :environment })
                  .lock
                  .to_a
      by_node = mitigated.to_h { |s| [s.node_id, s] }
      active_states = [
        ::Vps.object_states[:active],
        ::Vps.object_states[:suspended]
      ]
      affected = ::Vps.unscoped
                      .eager_load(:user, node: { location: :environment })
                      .where(node_id: by_node.keys, object_state: active_states)
                      .order(:id)
                      .lock
                      .to_a

      affected.each do |vps|
        ns = by_node.fetch(vps.node_id)
        rec = security_advisory_vpses.lock.find_or_initialize_by(vps:)
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
    user_counts = security_advisory_vpses.lock.pluck(:user_id).tally

    user_counts.each do |user_id, count|
      security_advisory_users.lock.find_or_initialize_by(user: ::User.lock.find(user_id)).tap do |rec|
        rec.vps_count = count
        rec.save!
      end
    end

    security_advisory_users.where.not(user_id: user_counts.keys).delete_all
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
    with_lock(requires_new: true) do
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
    @last_chain, = TransactionChains::SecurityAdvisories::Mail.fire(self, event, update)
  end

  protected

  def save_node_status!(status, attrs, translations)
    status.assign_attributes(attrs)
    if !draft? && !status.not_affected? && !status.mitigated?
      status.errors.add(:state, 'must be not_affected or mitigated for a published or retracted advisory')
      raise ActiveRecord::RecordInvalid, status
    end

    status.save!
    status.update_translations!(translations)
    rebuild_affected! unless draft?
  end

  def check_content_preconditions!(expected_content_revision:, expected_state:)
    if expected_state && expected_state.to_s != state
      raise StateMismatch,
            "security advisory changed (expected state #{expected_state}, current state #{state})"
    end

    check_content_revision!(expected_content_revision)
  end

  def check_content_revision!(expected_content_revision)
    return if expected_content_revision.to_i == content_revision

    raise RevisionMismatch,
          "security advisory changed (expected revision #{expected_content_revision}, " \
          "current revision #{content_revision})"
  end
end
