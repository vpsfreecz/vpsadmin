require_relative 'node'
require_relative 'object_state'
require_relative 'pool'
require_relative 'snapshot_download'
require_relative 'user'
require_relative 'user_device'
require_relative 'user_session'
require_relative 'user_totp_device'
require_relative 'vps'
require_relative 'vps_migration'

class NotificationTemplate < ApplicationRecord
  has_many :notification_template_variants, dependent: :destroy
  has_many :notification_template_email_recipients, dependent: :destroy
  has_many :email_recipients, through: :notification_template_email_recipients

  validates :name, :label, :template_id, presence: true, allow_blank: false
  validates :name, uniqueness: true

  has_paper_trail

  # @param name [Symbol]
  # @param opts [Hash]
  # @option opts [String] label
  # @option opts [String] desc description
  def self.role(name, opts)
    @roles ||= {}
    @roles[name] = opts
  end

  def self.roles
    @roles || {}
  end

  # @param id [Symbol]
  # @param opts [Hash] options
  # @option opts [String] name name with variables
  # @option opts [Array<Symbol>] roles
  # @option opts [String] desc description
  # @option opts [Hash] params description of variables found in template name
  # @option opts [Hash] vars description of variables passed to the template
  def self.register(id, opts = {})
    @templates ||= {}

    if @templates[id] && @templates[id][:vars]
      @templates[id][:vars].update(opts[:vars]) if opts[:vars]

    else
      @templates[id] = opts
    end
  end

  def self.templates
    @templates || {}
  end

  def self.resolve_name(name, params)
    tpl = templates[name]
    raise "Attempted to use an unregistered notification template '#{name}'" unless tpl

    return name if tpl[:name].nil?

    tpl[:name] % (params || {})
  end

  def self.find_resolved!(name, params = nil)
    find_by(name: resolve_name(name, params)).tap do |template|
      raise VpsAdmin::API::Exceptions::NotificationTemplateDoesNotExist, name unless template
    end
  end

  # Generate an e-mail from template
  # @param name [Symbol] template name
  # @param opts [Hash] options
  # @option opts [Hash] params parameters to be applied to the name
  # @option opts [User, nil] user whom to send mail
  # @option opts [Language, nil] language defaults to user's language
  # @option opts [Hash] vars variables passed to the template
  # @option opts [Array<String>] to
  # @option opts [Array<String>] cc
  # @option opts [Array<String>] bcc
  # @option opts [String] from
  # @option opts [String] reply_to
  # @option opts [String] return_path
  # @option opts [String] message_id
  # @option opts [String] in_reply_to
  # @option opts [String] references
  # @option opts [Boolean] include_default_recipients
  # @option opts [Boolean] include_template_recipients
  # @return [MailLog]
  def self.send_email!(name, opts = {})
    tpl = find_resolved!(name, opts[:params])

    lang = resolve_language(opts)
    variant = tpl.notification_template_variants.find_by(language: lang, protocol: 'email')
    raise VpsAdmin::API::Exceptions::NotificationTemplateDoesNotExist, name unless variant

    if opts[:vars]
      variant.resolve(
        opts[:vars],
        time_zone: opts[:time_zone] || opts[:user]&.time_zone
      )
    end

    mail = MailLog.new(
      user: opts[:user],
      notification_template: tpl,
      from: opts[:from] || variant.from,
      reply_to: opts[:reply_to] || variant.reply_to,
      return_path: opts[:return_path] || variant.return_path,
      message_id: opts[:message_id],
      in_reply_to: opts[:in_reply_to],
      references: opts[:references],
      subject: variant.subject,
      text_plain: variant.text,
      text_html: variant.html
    )

    recipients = { to: opts[:to] || [], cc: opts[:cc] || [], bcc: opts[:bcc] || [] }
    recipients[:to].concat(tpl.recipients(opts[:user])) if opts.fetch(:include_default_recipients, true)

    if opts.fetch(:include_template_recipients, true)
      tpl.email_recipients.each do |recp|
        recipients[:to].concat(recp.to.split(',')) if recp.to
        recipients[:cc].concat(recp.cc.split(',')) if recp.cc
        recipients[:bcc].concat(recp.bcc.split(',')) if recp.bcc
      end
    end

    %i[to cc bcc].each do |t|
      recipients[t].concat(opts[t]) if opts[t]
      mail.send("#{t}=", recipients[t].uniq.join(','))
    end

    mail.save!
    mail
  rescue VpsAdmin::API::Exceptions::NotificationTemplateDisabled
    nil
  end

  # @param opts [Hash] options
  # @option opts [String] subject (required)
  # @option opts [String] text_plain
  # @option opts [String] text_html
  # @option opts [User, nil] user whom to send mail
  # @option opts [Symbol] role contact email role
  # @option opts [Hash] vars variables passed to the template
  # @option opts [Array<String>] to
  # @option opts [Array<String>] cc
  # @option opts [Array<String>] bcc
  # @option opts [String] from (required)
  # @option opts [String] reply_to
  # @option opts [String] return_path
  # @option opts [String] message_id
  # @option opts [String] in_reply_to
  # @option opts [String] references
  # @return [MailLog]
  def self.send_custom_email(opts)
    if !opts[:subject]
      raise 'subject needed'

    elsif !opts[:text_plain] && !opts[:text_html]
      raise 'provide text_plain, text_html or both'

    elsif !opts[:from]
      raise 'from needed'
    end

    builder = NotificationTemplateVariant::TemplateBuilder.new(
      opts[:vars] || {},
      time_zone: opts[:time_zone] || opts[:user]&.time_zone
    )

    mail = MailLog.new(
      user: opts[:user],
      from: opts[:from],
      reply_to: opts[:reply_to],
      return_path: opts[:return_path],
      message_id: opts[:message_id],
      in_reply_to: opts[:in_reply_to],
      references: opts[:references],
      subject: builder.build(opts[:subject]),
      text_plain: opts[:text_plain] && builder.build(opts[:text_plain]),
      text_html: opts[:text_html] && builder.build(opts[:text_html])
    )

    recps = { to: opts[:to] || [], cc: opts[:cc] || [], bcc: opts[:bcc] || [] }

    recps[:to].concat(recipients(nil, opts[:user], [opts[:role]])) if opts[:user] && opts[:role]

    %i[to cc bcc].each do |t|
      mail.send("#{t}=", recps[t].uniq.join(','))
    end

    mail.save!
    mail
  end

  # Render a non-email protocol from a notification template.
  # @param protocol [String, Symbol]
  # @param name [Symbol]
  # @param opts [Hash]
  # @return [Hash] rendered protocol payload
  def self.render_protocol!(protocol, name, opts = {})
    tpl = find_resolved!(name, opts[:params])
    lang = resolve_language(opts)
    variant = tpl.notification_template_variants.find_by(language: lang, protocol: protocol.to_s)
    raise VpsAdmin::API::Exceptions::NotificationTemplateDoesNotExist, name unless variant

    variant.resolve(
      opts[:vars] || {},
      time_zone: opts[:time_zone] || opts[:user]&.time_zone
    )

    {
      template: tpl,
      variant:,
      subject: variant.subject,
      text: variant.text,
      html: variant.html,
      options: variant.options || {}
    }
  end

  def self.render_telegram!(name, opts = {})
    render_protocol!(:telegram, name, opts)
  end

  def self.render_sms!(name, opts = {})
    render_protocol!(:sms, name, opts)
  end

  def self.resolve_language(opts)
    opts[:language] ||
      opts[:user]&.language ||
      Language.find_by(code: 'en') ||
      Language.first ||
      raise(VpsAdmin::API::Exceptions::NotificationTemplateDoesNotExist, opts[:name])
  end

  # Returns a list of e-mail recipients, tries to find role recipients,
  # user template recipients and defaults to the primary e-mail address.
  # @param template [NotificationTemplate, nil]
  # @param user [User]
  # @param roles [Array, Symbol]
  # @return [Array<String>] list of e-mail addresses
  def self.recipients(template, user, roles)
    ret = []
    return ret unless user

    # Template recipients
    if template
      user.user_notification_template_recipients.where(
        notification_template: template
      ).each do |recp|
        raise VpsAdmin::API::Exceptions::NotificationTemplateDisabled, template.name if recp.disabled?

        ret.concat(recp.to.split(','))
      end
    end

    if ret.empty?
      user.user_email_role_recipients.where(role: roles).each do |recp|
        ret.concat(recp.to.split(','))
      end
    end

    ret << user.email if ret.empty?
    ret.uniq!
    ret
  end

  # Register built-in templates
  role :account, label: 'Account management'
  role :admin, label: 'System administrator'

  register :daily_report, vars: {
    date: Hash,
    users: Hash,
    vps: Hash,
    datasets: Hash,
    snapshots: Hash,
    downloads: Hash,
    chains: Hash,
    transactions: Hash
  }

  register :expiration_warning, name: 'expiration_%{object}_%{state}', params: {
    object: 'class name of the object nearing expiration, demodulized with underscores',
    state: 'one of lifetime states'
  }, roles: %i[account], public: true

  register :snapshot_download_ready, vars: {
    base_url: [String, 'URL to the web UI'],
    dl: ::SnapshotDownload
  }, roles: %i[admin], public: true

  register :user_create, vars: {
    user: ::User
  }, roles: %i[account]

  register :user_suspend, vars: {
    user: ::User,
    state: ::ObjectState
  }, roles: %i[account], public: true

  register :user_soft_delete, vars: {
    user: ::User,
    state: ::ObjectState
  }, roles: %i[account], public: true

  register :user_resume, vars: {
    user: ::User,
    state: ::ObjectState
  }, roles: %i[account], public: true

  register :user_revive, vars: {
    user: ::User,
    state: ::ObjectState
  }, roles: %i[account], public: true

  register :user_new_login, vars: {
    user: ::User,
    user_session: ::UserSession,
    user_device: ::UserDevice
  }, roles: %i[admin]

  register :user_new_token, vars: {
    user: ::User,
    user_session: ::UserSession
  }, roles: %i[admin]

  register :user_totp_recovery_code_used, vars: {
    user: ::User,
    totp_device: ::UserTotpDevice,
    request: Sinatra::Request,
    time: Time
  }, roles: %i[account]

  register :user_failed_logins, vars: {
    user: ::User,
    attempts: 'Array<Array<UserFailedLogin>>'
  }, roles: %i[account]

  register :vps_suspend, vars: {
    vps: ::Vps,
    state: ::ObjectState
  }, roles: %i[account admin], public: true

  register :vps_resume, vars: {
    vps: ::Vps,
    state: ::ObjectState
  }, roles: %i[account admin], public: true

  register :vps_migration_planned, vars: {
    m: ::VpsMigration,
    vps: ::Vps,
    src_node: ::Node,
    dst_node: ::Node
  }, roles: %i[admin], public: true

  register :vps_migration_begun, vars: {
    vps: ::Vps,
    src_node: ::Node,
    dst_node: ::Node,
    maintenance_window: ::Boolean,
    reason: String
  }, roles: %i[admin], public: true

  register :vps_migration_finished, vars: {
    vps: ::Vps,
    src_node: ::Node,
    dst_node: ::Node,
    maintenance_window: ::Boolean,
    reason: String
  }, roles: %i[admin], public: true

  register :vps_replaced, vars: {
    original_vps: ::Vps,
    new_vps: ::Vps,
    reason: String
  }, roles: %i[admin], public: true

  register :vps_resources_change, vars: {
    vps: ::Vps,
    admin: ::User,
    reason: String
  }, roles: %i[admin], public: true

  register :vps_dns_resolver_change, vars: {
    vps: ::Vps,
    old_dns_resolver: ::DnsResolver,
    new_dns_resolver: ::DnsResolver
  }, roles: %i[admin], public: true

  register :vps_oom_report, vars: {
    base_url: [String, 'URL to the web UI'],
    vps: ::Vps,
    all_oom_reports: 'Array<::OomReport>',
    all_oom_count: Integer,
    selected_oom_reports: 'Array<::OomReport>',
    selected_oom_count: Integer
  }, roles: %i[admin], public: true

  register :vps_oom_prevention, vars: {
    base_url: [String, 'URL to the web UI'],
    vps: ::Vps,
    action: ':restart, :stop',
    ooms_in_period: Integer,
    period_seconds: Integer
  }, roles: %i[admin], public: true

  register :vps_dataset_expanded, vars: {
    base_url: [String, 'URL to the web UI'],
    vps: ::Vps,
    expansion: ::DatasetExpansion,
    dataset: ::Dataset
  }, roles: %i[admin], public: true

  register :vps_dataset_shrunk, vars: {
    base_url: [String, 'URL to the web UI'],
    vps: ::Vps,
    expansion: ::DatasetExpansion,
    dataset: ::Dataset
  }, roles: %i[admin], public: true

  register :vps_stopped_over_quota, vars: {
    base_url: [String, 'URL to the web UI'],
    vps: ::Vps,
    expansion: ::DatasetExpansion,
    dataset: ::Dataset
  }, roles: %i[admin], public: true

  register :vps_network_disabled, vars: {
    user: ::User,
    vps: ::Vps,
    reason: String
  }, roles: %i[admin], public: true

  register :vps_network_enabled, vars: {
    user: ::User,
    vps: ::Vps,
    reason: String
  }, roles: %i[admin], public: true

  register :vps_incident_report, vars: {
    base_url: [String, 'URL to the web UI'],
    user: ::User,
    vps: ::Vps,
    incident: ::IncidentReport
  }, roles: %i[admin], public: true

  register :security_advisory_user_announce, vars: {
    advisory: '::SecurityAdvisory',
    a: '::SecurityAdvisory',
    user: ::User,
    vpses: 'SecurityAdvisoryVps relation',
    webui_url: String
  }, roles: %i[admin], public: true

  register :security_advisory_user_update, vars: {
    advisory: '::SecurityAdvisory',
    a: '::SecurityAdvisory',
    update: '::SecurityAdvisoryUpdate',
    user: ::User,
    vpses: 'SecurityAdvisoryVps relation',
    webui_url: String
  }, roles: %i[admin], public: true

  register :dataset_migration_begun, vars: {
    dataset: ::Dataset,
    src_pool: ::Pool,
    dst_pool: ::Pool,
    exports: 'Array<Export>',
    export_mounts: 'Array<ExportMount>',
    vpses: 'Array<Vps>',
    restart_vps: ::Boolean,
    maintenance_window: ::Boolean,
    maintenance_windows: 'Array<MaintenanceWindow>',
    custom_window: ::Boolean,
    reason: String
  }, roles: %i[admin], public: true

  register :dataset_migration_finished, vars: {
    dataset: ::Dataset,
    src_pool: ::Pool,
    dst_pool: ::Pool,
    exports: 'Array<Export>',
    export_mounts: 'Array<ExportMount>',
    vpses: 'Array<Vps>',
    restart_vps: ::Boolean,
    maintenance_window: ::Boolean,
    maintenance_windows: 'Array<MaintenanceWindow>',
    custom_window: ::Boolean,
    reason: String
  }, roles: %i[admin], public: true

  enum :user_visibility, %i[default visible invisible]

  def recipients(user)
    self.class.recipients(self, user, desc[:roles])
  end

  def desc
    self.class.templates[template_id.to_sym] || {}
  end
end
