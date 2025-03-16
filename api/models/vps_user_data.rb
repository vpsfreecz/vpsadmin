require 'yaml'

class VpsUserData < ApplicationRecord
  FORMATS = %w[
    script
    cloudinit_config
    cloudinit_script
    nixos_configuration
    nixos_flake_configuration
    nixos_flake_uri
  ].freeze

  belongs_to :user

  validates :label, :format, :content, presence: true
  validates :label, length: { maximum: 255 }
  validates :format, inclusion: { in: FORMATS }
  validates :content, length: { maximum: 65_536 }
  validate :check_content

  protected

  def check_content
    case format
    when 'cloudinit_config'
      begin
        YAML.safe_load(content)
      rescue StandardError
        errors.add(:content, 'unable to parse as YAML')
      end

    when 'script', 'cloudinit_script'
      line = content.each_line.first

      if line.nil? || !line.start_with?('#!')
        errors.add(:content, 'script must start with a shebang on the first line')
      end

    when 'nixos_configuration', 'nixos_flake_configuration'
      unless content.lstrip.start_with?('{')
        errors.add(:content, "must start with '{'")
      end

      unless content.rstrip.end_with?('}')
        errors.add(:content, "must end with '{'")
      end

    when 'nixos_flake_uri'
      if /\s/ =~ content
        errors.add(:content, 'must not contain whitespace')
      end
    end
  end
end
