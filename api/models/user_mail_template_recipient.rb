class UserMailTemplateRecipient < ApplicationRecord
  belongs_to :user
  belongs_to :mail_template

  before_validation :clean_emails
  validate :check_emails

  # @param user [User]
  def self.all_templates_for(user)
    ret = includes(:mail_template).where(user:).to_a

    ::MailTemplate.where.not(
      id: ret.map(&:mail_template_id)
    ).each do |tpl|
      next unless tpl.desc[:public]

      ret << new(
        user:,
        mail_template: tpl,
        to: nil
      )
    end

    ret.select do |recp|
      if recp.mail_template.user_visibility == 'default'
        recp.mail_template.desc[:public]

      else
        recp.mail_template.user_visibility == 'visible'
      end
    end.sort do |a, b|
      a.mail_template.name <=> b.mail_template.name
    end
  end

  # @param user [User]
  # @param template [MailTemplate]
  # @param attrs [Hash]
  def self.handle_update!(user, template, attrs)
    recp = nil
    attrs = attrs.dup
    enabled = attrs[:enabled]
    to_present = attrs.has_key?(:to)
    to_value = attrs[:to]
    to_blank = !to_present || to_value.nil? || to_value.to_s.strip.empty?
    empty = to_blank && (enabled.nil? || enabled)

    attrs.delete(:enabled) if enabled.nil?

    if empty
      placeholder = new(
        user:,
        mail_template: template
      )
    end

    transaction do
      recp = find_by(
        user:,
        mail_template: template
      )

      if recp
        if empty
          recp.destroy!
          recp = placeholder

        else
          attrs[:to] = '' if to_present && to_blank
          recp.update!(attrs)
        end

      elsif empty
        recp = placeholder

      else
        attrs[:to] = '' if to_blank
        recp = new(
          user:,
          mail_template: template
        )
        recp.assign_attributes(attrs)
        recp.save!
      end
    end

    recp
  end

  def name
    mail_template.name
  end

  def label
    mail_template.label
  end

  def description
    mail_template.desc[:desc]
  end

  def disabled?
    !enabled
  end

  protected

  def clean_emails
    return unless to

    to.gsub!(/\s/, '')
  end

  def check_emails
    if to.blank?
      errors.add(:to, "can't be blank") unless enabled == false
      return
    end

    to.split(',').each do |mail|
      next if /@/ =~ mail.strip

      errors.add(:to, "'#{mail}' is not a valid e-mail address")
    end
  end
end
