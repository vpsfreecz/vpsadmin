class UserNotificationTemplateRecipient < ApplicationRecord
  belongs_to :user
  belongs_to :notification_template

  before_validation :clean_emails
  validate :check_emails

  # @param user [User]
  def self.all_templates_for(user)
    ret = includes(:notification_template).where(user:).to_a

    ::NotificationTemplate.where.not(
      id: ret.map(&:notification_template_id)
    ).each do |tpl|
      next unless tpl.desc[:public]

      ret << new(
        user:,
        notification_template: tpl,
        to: nil
      )
    end

    ret.select do |recp|
      if recp.notification_template.user_visibility == 'default'
        recp.notification_template.desc[:public]

      else
        recp.notification_template.user_visibility == 'visible'
      end
    end.sort do |a, b|
      a.notification_template.name <=> b.notification_template.name
    end
  end

  # @param user [User]
  # @param template [NotificationTemplate]
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
        notification_template: template
      )
    end

    transaction do
      recp = find_by(
        user:,
        notification_template: template
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
          notification_template: template
        )
        recp.assign_attributes(attrs)
        recp.save!
      end
    end

    recp
  end

  def name
    notification_template.name
  end

  def label
    notification_template.label
  end

  def description
    notification_template.desc[:desc]
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
