class MailTemplate < ActiveRecord::Base
  has_many :mail_template_translations, dependent: :destroy
  has_many :mail_template_recipients, dependent: :destroy
  has_many :mail_recipients, through: :mail_template_recipients

  has_paper_trail

  # @param id [Symbol]
  # @param opts [Hash] options
  # @option opts [String] name name with variables
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
    fail "Attempted to use an unregistered mail template '#{name}'" unless tpl

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
        text_html: tr.text_html,
    )

    recipients = {to: opts[:to] || [], cc: opts[:cc] || [], bcc: opts[:bcc] || []}
    recipients[:to] << opts[:user].email if opts[:user]

    tpl.mail_recipients.each do |recp|
      recipients[:to].concat(recp.to.split(',')) if recp.to
      recipients[:cc].concat(recp.cc.split(',')) if recp.cc
      recipients[:bcc].concat(recp.bcc.split(',')) if recp.bcc
    end

    %i(to cc bcc).each do |t|
      recipients[t].concat(opts[t]) if opts[t]
      mail.send("#{t}=", recipients[t].uniq.join(','))
    end

    mail.save!
    mail
  end

  # Register built-in templates
  register :daily_report, vars: {
      base_url: [String, 'URL to the web UI'],
      date: Hash,
      users: Hash,
      vps: Hash,
      datasets: Hash,
      snapshots: Hash,
      downloads: Hash,
      chains: Hash,
      transactions: Hash,
  }
  register :expiration_warning, name: "expiration_%{object}_%{state}", params: {
      object: 'class name of the object nearing expiration, demodulized with underscores',
      state: 'one of lifetime states',
  }
  register :snapshot_download_ready, vars: {
      dl: ::SnapshotDownload,
  }
  register :user_create, vars: {
      user: ::User,
  }
  register :user_suspend, vars: {
      user: ::User,
      state: ::ObjectState,
  }
  register :user_soft_delete, vars: {
      user: ::User,
      state: ::ObjectState,
  }
  register :user_resume, vars: {
      user: ::User,
      state: ::ObjectState,
  }
  register :user_revive, vars: {
      user: ::User,
      state: ::ObjectState,
  }
  register :vps_suspend, vars: {
      vps: ::Vps,
      state: ::ObjectState,
  }
  register :vps_resume, vars: {
      vps: ::Vps,
      state: ::ObjectState,
  }
  register :vps_migration_planned, vars: {
      m: ::VpsMigration,
      vps: ::Vps,
      src_node: ::Node,
      dst_node: ::Node,
  }
  register :vps_migration_begun, vars: {
      vps: ::Vps,
      src_node: ::Node,
      dst_node: ::Node,
      outage_window: ::Boolean,
      reason: String,
  }
  register :vps_migration_finished, vars: {
      vps: ::Vps,
      src_node: ::Node,
      dst_node: ::Node,
      outage_window: ::Boolean,
      reason: String,
  }
  register :vps_resources_change, vars: {
      vps: ::Vps,
      admin: ::User,
      reason: String,
  }
end
