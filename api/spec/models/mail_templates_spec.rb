# frozen_string_literal: true

require 'fileutils'
require 'tmpdir'

RSpec.describe VpsAdmin::API::MailTemplates do
  def write_template(dir, name, meta:, plain:)
    path = File.join(dir, name)
    FileUtils.mkdir_p(path)
    File.write(File.join(path, 'meta.rb'), meta)
    File.write(File.join(path, 'en.plain.erb'), plain)
  end

  it 'loads template directories in vpsadmin-mail-templates format' do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, '.gems'))

      write_template(
        dir,
        'spec_directory_template',
        meta: <<~RUBY,
          template :user_create do
            label 'Directory template'
            from 'from@example.test'

            lang :en do
              subject 'Directory subject'
            end
          end
        RUBY
        plain: 'Directory body'
      )

      template = described_class.find_templates([dir]).first

      expect(template.params).to include(
        name: 'spec_directory_template',
        label: 'Directory template',
        template_id: 'user_create',
        user_visibility: 'default'
      )
      expect(template.translations.first.params).to include(
        from: 'from@example.test',
        subject: 'Directory subject',
        text_plain: 'Directory body'
      )
    end
  end

  it 'creates missing templates and translations' do
    Dir.mktmpdir do |dir|
      write_template(
        dir,
        'spec_install_template',
        meta: <<~RUBY,
          template :user_create do
            label 'Install template'
            from 'from@example.test'
            subject 'Install subject'
          end
        RUBY
        plain: 'Install body'
      )

      result = described_class.install_defaults!(paths: [dir])

      template = MailTemplate.find_by!(name: 'spec_install_template')
      translation = template.mail_template_translations.find_by!(language: SpecSeed.language)

      expect(result).to eq(templates_created: 1, translations_created: 1)
      expect(template.template_id).to eq('user_create')
      expect(translation.text_plain).to eq('Install body')
    end
  end

  it 'does not overwrite existing templates or translations' do
    template = MailTemplate.create!(
      name: 'spec_existing_template',
      label: 'Existing template',
      template_id: 'daily_report'
    )
    template.mail_template_translations.create!(
      language: SpecSeed.language,
      from: 'custom@example.test',
      subject: 'Custom subject',
      text_plain: 'Custom body'
    )

    Dir.mktmpdir do |dir|
      write_template(
        dir,
        'spec_existing_template',
        meta: <<~RUBY,
          template :user_create do
            label 'Changed template'
            from 'changed@example.test'
            subject 'Changed subject'
          end
        RUBY
        plain: 'Changed body'
      )

      result = described_class.install_defaults!(paths: [dir])
      template.reload
      translation = template.mail_template_translations.find_by!(language: SpecSeed.language)

      expect(result).to eq(templates_created: 0, translations_created: 0)
      expect(template.label).to eq('Existing template')
      expect(template.template_id).to eq('daily_report')
      expect(translation.from).to eq('custom@example.test')
      expect(translation.text_plain).to eq('Custom body')
    end
  end

  it 'generates neutral English fallbacks for registered templates' do
    generated = described_class.generated_templates.to_h do |template|
      [template.name, template.id]
    end

    expect(generated).to include(
      'user_create' => 'user_create',
      'daily_report' => 'daily_report',
      'expiration_user_active' => 'expiration_warning'
    )
  end
end
