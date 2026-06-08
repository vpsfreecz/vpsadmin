class MailTemplateTranslation < ApplicationRecord
  belongs_to :language
  belongs_to :mail_template

  validates :mail_template, presence: true
  validates :language, presence: true
  validates :from, :subject, presence: true, allow_blank: false
  validates :language, uniqueness: { scope: :mail_template }

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
  end

  def resolve(vars, time_zone: nil)
    b = TemplateBuilder.new(vars, time_zone:)
    self.subject = b.build(subject)
    self.text_plain = b.build(text_plain) if text_plain
    self.text_html = b.build(text_html) if text_html
  end
end
