class MailTemplate < ActiveRecord::Base
  has_many :mail_template_recipients
  has_many :mail_recipients, through: :mail_template_recipients

  class TemplateBuilder
    def initialize(vars)
      vars.each do |k, v|
        instance_variable_set("@#{k}", v)
      end
    end

    def build(tpl)
      ERB.new(tpl).result(binding)
    end
  end

  def self.send_mail!(name, opts = {})
    tpl = MailTemplate.find_by(name: name)
    raise VpsAdmin::API::Exceptions::MailTemplateDoesNotExist, name unless tpl
    tpl.resolve(opts[:vars]) if opts[:vars]

    mail = MailLog.new(
        user: opts[:user],
        mail_template: tpl,
        from: opts[:from] || tpl.from,
        reply_to: opts[:reply_to] || tpl.reply_to,
        return_path: opts[:return_path] || tpl.return_path,
        subject: tpl.subject,
        text_plain: tpl.text_plain,
        text_html: tpl.text_html,
    )

    recipients = {to: [], cc: [], bcc: []}
    recipients[:to] << opts[:user].m_mail if opts[:user]

    tpl.mail_recipients.each do |recp|
      recipients[:to].concat(recp.to.split(','))
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

  def resolve(vars)
    b = TemplateBuilder.new(vars)
    self.subject = b.build(self.subject)
    self.text_plain = b.build(self.text_plain) if self.text_plain
    self.text_html = b.build(self.text_html) if self.text_html
  end
end
