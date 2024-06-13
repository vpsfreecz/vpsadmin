require_relative 'node'
require_relative 'object_state'
require_relative 'snapshot_download'
require_relative 'user'
require_relative 'user_device'
require_relative 'user_session'
require_relative 'user_totp_device'
require_relative 'vps'
require_relative 'vps_migration'

class MailTemplate < ActiveRecord::Base
  has_many :mail_template_translations, dependent: :destroy
  has_many :mail_template_recipients, dependent: :destroy
  has_many :mail_recipients, through: :mail_template_recipients

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
    raise "Attempted to use an unregistered mail template '#{name}'" unless tpl

    return name if tpl[:name].nil?

    tpl[:name] % (params || {})
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
  # @return [MailLog]
  def self.send_mail!(name, opts = {})
    tpl = MailTemplate.find_by(name: resolve_name(name, opts[:params]))
    raise VpsAdmin::API::Exceptions::MailTemplateDoesNotExist, name unless tpl

    lang = opts[:language] || opts[:user].language
    tr = tpl.mail_template_translations.find_by(language: lang)
    raise VpsAdmin::API::Exceptions::MailTemplateDoesNotExist, name unless tr

    tr.resolve(opts[:vars]) if opts[:vars]

    mail = MailLog.new(
      user: opts[:user],
      mail_template: tpl,
      from: opts[:from] || tr.from,
      reply_to: opts[:reply_to] || tr.reply_to,
      return_path: opts[:return_path] || tr.return_path,
      message_id: opts[:message_id],
      in_reply_to: opts[:in_reply_to],
      references: opts[:references],
      subject: tr.subject,
      text_plain: tr.text_plain,
      text_html: tr.text_html
    )

    recipients = { to: opts[:to] || [], cc: opts[:cc] || [], bcc: opts[:bcc] || [] }
    recipients[:to].concat(tpl.recipients(opts[:user]))

    tpl.mail_recipients.each do |recp|
      recipients[:to].concat(recp.to.split(',')) if recp.to
      recipients[:cc].concat(recp.cc.split(',')) if recp.cc
      recipients[:bcc].concat(recp.bcc.split(',')) if recp.bcc
    end

    %i[to cc bcc].each do |t|
      recipients[t].concat(opts[t]) if opts[t]
      mail.send("#{t}=", recipients[t].uniq.join(','))
    end

    mail.save!
    mail
  rescue VpsAdmin::API::Exceptions::MailTemplateDisabled
    nil
  end

  # @param opts [Hash] options
  # @option opts [String] subject (required)
  # @option opts [String] text_plain
  # @option opts [String] text_html
  # @option opts [User, nil] user whom to send mail
  # @option opts [Symbol] role contact mail role
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
  def self.send_custom(opts)
    if !opts[:subject]
      raise 'subject needed'

    elsif !opts[:text_plain] && !opts[:text_html]
      raise 'provide text_plain, text_html or both'

    elsif !opts[:from]
      raise 'from needed'
    end

    builder = MailTemplateTranslation::TemplateBuilder.new(opts[:vars] || {})

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

  # Returns a list of e-mail recipients, tries to find role recipients,
  # user template recipients and defaults to the primary e-mail address.
  # @param template [MailTemplate, nil]
  # @param user [User]
  # @param roles [Array, Symbol]
  # @return [Array<String>] list of e-mail addresses
  def self.recipients(template, user, roles)
    ret = []
    return ret unless user

    # Template recipients
    if template
      user.user_mail_template_recipients.where(
        mail_template: template
      ).each do |recp|
        raise VpsAdmin::API::Exceptions::MailTemplateDisabled, name if recp.disabled?

        ret.concat(recp.to.split(','))
      end
    end

    if ret.empty?
      user.user_mail_role_recipients.where(role: roles).each do |recp|
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
  }, roles: %i[account]

  register :user_new_token, vars: {
    user: ::User,
    user_session: ::UserSession
  }, roles: %i[account]

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
    oom_reports: 'Array<::OomReport>'
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

  register :vps_incident_report, vars: {
    base_url: [String, 'URL to the web UI'],
    user: ::User,
    vps: ::Vps,
    incident: ::IncidentReport
  }, roles: %i[admin], public: true

  enum user_visibility: %i[default visible invisible]

  def recipients(user)
    self.class.recipients(self, user, desc[:roles])
  end

  def desc
    self.class.templates[template_id.to_sym]
  end
end
