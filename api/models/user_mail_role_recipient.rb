class UserMailRoleRecipient < ActiveRecord::Base
  belongs_to :user

  before_validation :clean_emails
  validate :check_emails

  # @param user [User]
  def self.all_roles_for(user)
    ret = self.where(user: user).to_a

    ::MailTemplate.roles.each do |role, opts|
      next if ret.detect { |recp| recp.role == role.to_s }

      ret << new(
          user: user,
          role: role.to_s,
          to: nil,
      )
    end

    ret.sort { |a, b| a.role <=> b.role }
  end

  # @param user [User]
  # @param role [String]
  # @param attrs [Hash]
  def self.handle_update!(user, role, attrs)
    recp = nil
    empty = attrs[:to].nil? || attrs[:to].strip.empty?

    if empty
      placeholder = new(
          user: user,
          role: role,
      )
    end

    transaction do
      recp = find_by(
          user: user,
          role: role,
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
            user: user,
            role: role,
        )
        recp.assign_attributes(attrs)
        recp.save!
      end
    end

    recp
  end

  def label
    ::MailTemplate.roles[role.to_sym][:label]
  end

  def description
    ::MailTemplate.roles[role.to_sym][:desc]
  end

  protected
  def clean_emails
    return unless self.to
    self.to.gsub!(/\s/, '')
  end

  def check_emails
    return unless self.to

    self.to.split(',').each do |mail|
      next if /@/ =~ mail.strip

      errors.add(:to, "'#{mail}' is not a valid e-mail address")
    end
  end
end
