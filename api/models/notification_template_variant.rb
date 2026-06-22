class NotificationTemplateVariant < ApplicationRecord
  belongs_to :language
  belongs_to :notification_template

  validates :notification_template, presence: true
  validates :language, presence: true
  validates :protocol, presence: true
  validates :language, uniqueness: { scope: %i[notification_template protocol] }
  validate :check_protocol_content

  enum :protocol, %i[email telegram sms], suffix: true
  serialize :options, coder: JSON

  has_paper_trail

  class TemplateBuilder
    def initialize(vars, time_zone: nil)
      @time_zone = time_zone

      vars.each do |k, v|
        instance_variable_set("@#{k}", v)
      end
    end

    def build(tpl)
      ERB.new(tpl, trim_mode: '-').result(binding)
    end

    def local_time(value, format = VpsAdmin::API::TimeZones::DEFAULT_TIME_FORMAT)
      VpsAdmin::API::TimeZones.format_time(value, time_zone: @time_zone, format:)
    end

    def local_date(value, format = VpsAdmin::API::TimeZones::DEFAULT_DATE_FORMAT)
      VpsAdmin::API::TimeZones.format_date(value, time_zone: @time_zone, format:)
    end

    def webui_url(path = nil)
      base_url = VpsAdmin::API::Events.webui_url
      return base_url if path.blank?

      "#{base_url}/#{path.to_s.delete_prefix('/')}"
    end
  end

  def resolve(vars, time_zone: nil)
    b = TemplateBuilder.new(vars, time_zone:)
    self.subject = b.build(subject) if subject
    self.text = b.build(text) if text
    self.html = b.build(html) if html
  end

  protected

  def check_protocol_content
    case protocol&.to_sym
    when :email
      errors.add(:from, "can't be blank") if from.blank?
      errors.add(:subject, "can't be blank") if subject.blank?
      errors.add(:text, 'or html must be present') if text.blank? && html.blank?
    when :telegram, :sms
      errors.add(:text, "can't be blank") if text.blank?
    end
  end
end
