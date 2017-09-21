class MailTemplateTranslation < ActiveRecord::Base
  belongs_to :language
  belongs_to :mail_template

  has_paper_trail

  class TemplateBuilder
    def initialize(vars)
      vars.each do |k, v|
        instance_variable_set("@#{k}", v)
      end
    end

    def build(tpl)
      ERB.new(tpl, nil, '-').result(binding)
    end
  end

  def resolve(vars)
    b = TemplateBuilder.new(vars)
    self.subject = b.build(self.subject)
    self.text_plain = b.build(self.text_plain) if self.text_plain
    self.text_html = b.build(self.text_html) if self.text_html
  end
end
