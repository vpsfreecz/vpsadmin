class MailTemplateTranslation < ApplicationRecord
  belongs_to :language
  belongs_to :mail_template

  validates :mail_template, presence: true
  validates :language, presence: true
  validates :from, :subject, presence: true, allow_blank: false
  validates :language, uniqueness: { scope: :mail_template }

  has_paper_trail

  class TemplateBuilder
    def initialize(vars)
      vars.each do |k, v|
        instance_variable_set("@#{k}", v)
      end
    end

    def build(tpl)
      ERB.new(tpl, trim_mode: '-').result(binding)
    end
  end

  def resolve(vars)
    b = TemplateBuilder.new(vars)
    self.subject = b.build(subject)
    self.text_plain = b.build(text_plain) if text_plain
    self.text_html = b.build(text_html) if text_html
  end
end
