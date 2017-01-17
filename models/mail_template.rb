class MailTemplate < ActiveRecord::Base
  has_many :mail_template_translations, dependent: :destroy
  has_many :mail_template_recipients, dependent: :destroy
  has_many :mail_recipients, through: :mail_template_recipients

  has_paper_trail
  
  def self.send_mail!(name, opts = {})
    tpl = MailTemplate.find_by(name: name)
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
        subject: tr.subject,
        text_plain: tr.text_plain,
        text_html: tr.text_html,
    )

    recipients = {to: [], cc: [], bcc: []}
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
end
