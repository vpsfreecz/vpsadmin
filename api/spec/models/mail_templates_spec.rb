# frozen_string_literal: true

require 'fileutils'
require 'tmpdir'
require 'erb'

RSpec.describe VpsAdmin::API::MailTemplates do
  def write_template(dir, name, meta:, plain:)
    path = File.join(dir, name)
    FileUtils.mkdir_p(path)
    File.write(File.join(path, 'meta.rb'), meta)
    File.write(File.join(path, 'en.plain.erb'), plain)
  end

  def compile_erb(source)
    RubyVM::InstructionSequence.compile(ERB.new(source, trim_mode: '-').src)
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

  it 'repairs known language labels created from template language codes' do
    language = Language.find_or_initialize_by(code: 'cs')
    language.label = 'cs'
    language.save!

    described_class.send(:ensure_language!, 'cs')

    expect(language.reload.label).to eq('Česky')
  end

  it 'uses the configured support mail as the default sender' do
    SysConfig.find_or_create_by!(category: 'core', name: 'support_mail').update!(
      value: 'support@example.test'
    )

    Dir.mktmpdir do |dir|
      write_template(
        dir,
        'spec_default_sender_template',
        meta: <<~RUBY,
          template :user_create do
            label 'Default sender template'
            subject 'Default sender subject'
          end
        RUBY
        plain: 'Default sender body'
      )

      translation = described_class.find_templates([dir]).first.translations.first

      expect(translation.params).to include(
        from: 'support@example.test',
        reply_to: 'support@example.test',
        return_path: 'support@example.test'
      )
    end
  end

  it 'renders template times in the delivery user time zone' do
    MailTemplate.register :spec_time_zone_template, name: 'spec_time_zone_template'
    template = MailTemplate.create!(
      name: 'spec_time_zone_template',
      label: 'Spec time zone template',
      template_id: 'spec_time_zone_template'
    )
    template.mail_template_translations.create!(
      language: SpecSeed.language,
      from: 'noreply@test.invalid',
      subject: 'At <%= local_time(@time, "%Y-%m-%d %H:%M %Z") %>',
      text_plain: 'At <%= local_time(@time, "%Y-%m-%d %H:%M %Z") %>'
    )
    SpecSeed.user.update!(time_zone: 'America/New_York')

    mail = MailTemplate.send_mail!(
      :spec_time_zone_template,
      user: SpecSeed.user,
      vars: { time: Time.utc(2024, 1, 1, 12, 0, 0) }
    )

    expect(mail.subject).to eq('At 2024-01-01 07:00 EST')
    expect(mail.text_plain).to eq('At 2024-01-01 07:00 EST')
  end

  it 'falls back to English when the user language translation is missing' do
    language = Language.find_or_create_by!(code: 'cs') do |lang|
      lang.label = 'Česky'
    end
    user = SpecSeed.user
    user.update!(language:)

    MailTemplate.register :spec_language_fallback_template, name: 'spec_language_fallback_template'
    template = MailTemplate.create!(
      name: 'spec_language_fallback_template',
      label: 'Spec language fallback template',
      template_id: 'spec_language_fallback_template'
    )
    template.mail_template_translations.create!(
      language: SpecSeed.language,
      from: 'noreply@test.invalid',
      subject: 'English subject',
      text_plain: 'English body'
    )

    mail = MailTemplate.send_mail!(
      :spec_language_fallback_template,
      user:
    )

    expect(mail.subject).to eq('English subject')
    expect(mail.text_plain).to eq('English body')
  end

  it 'ships directory-backed English templates for all registered defaults' do
    templates = described_class.find_templates(described_class.default_template_paths).to_h do |template|
      [template.name, template]
    end

    described_class.required_default_templates.each do |name, template_id|
      template = templates[name]

      expect(template).to be_present, "#{name} is missing"
      expect(template.id.to_s).to eq(template_id)
      expect(template.translations.map(&:lang)).to include('en')
    end
  end

  it 'ships usable built-in template content' do
    templates = described_class.find_templates(described_class.default_template_paths)
    expect(templates).not_to be_empty

    templates.each do |template|
      translation = template.translations.detect { |tr| tr.lang == 'en' }
      expect(translation).to be_present, "#{template.name} is missing English"

      params = translation.params
      expect(params[:subject]).to be_present
      expect(params[:text_plain]).to be_present

      [params[:subject], params[:text_plain], params[:text_html]].compact.each do |source|
        compile_erb(source)
      end

      content = [
        template.name,
        template.params[:label],
        params[:subject],
        params[:text_plain],
        params[:text_html]
      ].compact.join("\n")

      expect(content).not_to include('Template:')
      expect(content).not_to match(/vpsFree/i)
      expect(content).not_to match(/\bmember(ship|s)?\b/i)
    end
  end
end
