class UserMailRoleRecipient < ApplicationRecord
  belongs_to :user

  before_validation :clean_emails
  validate :check_role
  validate :check_emails

  # @param user [User]
  def self.all_roles_for(user)
    ret = where(user:, role: registered_roles).to_a

    ::MailTemplate.roles.each_key do |role|
      next if ret.detect { |recp| recp.role == role.to_s }

      ret << new(
        user:,
        role: role.to_s,
        to: nil
      )
    end

    ret.sort { |a, b| a.role <=> b.role }
  end

  def self.registered_roles
    ::MailTemplate.roles.keys.map(&:to_s)
  end

  def self.registered_role?(role)
    registered_roles.include?(role.to_s)
  end

  def self.role_config(role)
    ::MailTemplate.roles.each do |name, opts|
      return opts if name.to_s == role.to_s
    end

    nil
  end

  # @param user [User]
  # @param role [String]
  # @param attrs [Hash]
  def self.handle_update!(user, role, attrs)
    check_role!(user, role)

    recp = nil
    empty = attrs[:to].nil? || attrs[:to].strip.empty?

    if empty
      placeholder = new(
        user:,
        role:
      )
    end

    transaction do
      recp = find_by(
        user:,
        role:
      )

      if recp
        if empty
          recp.destroy!
          recp = placeholder

        else
          recp.update!(attrs)
        end

      elsif empty
        recp = placeholder

      else
        recp = new(
          user:,
          role:
        )
        recp.assign_attributes(attrs)
        recp.save!
      end
    end

    recp
  end

  def self.check_role!(user, role)
    return if registered_role?(role)

    recp = new(user:, role:)
    recp.errors.add(:role, 'is not a registered mail role')
    raise ActiveRecord::RecordInvalid, recp
  end

  def label
    self.class.role_config(role)&.fetch(:label, nil)
  end

  def description
    self.class.role_config(role)&.fetch(:desc, nil)
  end

  protected

  def clean_emails
    return unless to

    to.gsub!(/\s/, '')
  end

  def check_emails
    return unless to

    to.split(',').each do |mail|
      next if /@/ =~ mail.strip

      errors.add(:to, "'#{mail}' is not a valid e-mail address")
    end
  end

  def check_role
    return if self.class.registered_role?(role)

    errors.add(:role, 'is not a registered mail role')
  end
end
