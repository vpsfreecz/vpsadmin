# frozen_string_literal: true

require 'fileutils'
require 'tmpdir'
require 'erb'

RSpec.describe VpsAdmin::API::NotificationTemplates do
  def write_template(dir, name, meta:, text:, telegram_text: nil, sms_text: nil)
    base = File.join(dir, 'templates')
    path = File.join(base, name)
    email_path = File.join(path, 'email')
    telegram_path = File.join(path, 'telegram')
    sms_path = File.join(path, 'sms')
    FileUtils.mkdir_p(email_path)
    FileUtils.mkdir_p(telegram_path)
    FileUtils.mkdir_p(sms_path)
    File.write(File.join(path, 'meta.rb'), meta)
    File.write(File.join(email_path, 'en.subject.erb'), 'Directory subject')
    File.write(File.join(email_path, 'en.text.erb'), text)
    File.write(File.join(telegram_path, 'en.text.erb'), telegram_text || 'Telegram body')
    File.write(File.join(sms_path, 'en.text.erb'), sms_text || 'SMS body')
    base
  end

  def compile_erb(source)
    RubyVM::InstructionSequence.compile(ERB.new(source, trim_mode: '-').src)
  end

  it 'loads template directories in vpsadmin-notification-templates format' do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, '.gems'))

      write_template(
        dir,
        'spec_directory_template',
        meta: <<~RUBY,
          template :user_create do
            label 'Directory template'
            protocol :email do
              lang :en do
                from 'from@example.test'
              end
            end
          end
        RUBY
        text: 'Directory body'
      )

      template = described_class.find_templates([File.join(dir, 'templates')]).first

      expect(template.params).to include(
        name: 'spec_directory_template',
        label: 'Directory template',
        template_id: 'user_create',
        user_visibility: 'default'
      )
      expect(template.variants.find { |v| v.protocol == 'email' }.params).to include(
        protocol: 'email',
        from: 'from@example.test',
        subject: 'Directory subject',
        text: 'Directory body'
      )
      expect(template.variants.find { |v| v.protocol == 'telegram' }.params).to include(
        protocol: 'telegram',
        text: 'Telegram body'
      )
      expect(template.variants.find { |v| v.protocol == 'sms' }.params).to include(
        protocol: 'sms',
        text: 'SMS body'
      )
    end
  end

  it 'creates missing templates and variants' do
    Dir.mktmpdir do |dir|
      write_template(
        dir,
        'spec_install_template',
        meta: <<~RUBY,
          template :user_create do
            label 'Install template'
            protocol :email do
              from 'from@example.test'
            end
          end
        RUBY
        text: 'Install body'
      )

      result = described_class.install_defaults!(paths: [File.join(dir, 'templates')])

      template = NotificationTemplate.find_by!(name: 'spec_install_template')
      variant = template.notification_template_variants.find_by!(language: SpecSeed.language, protocol: 'email')
      telegram = template.notification_template_variants.find_by!(language: SpecSeed.language, protocol: 'telegram')
      sms = template.notification_template_variants.find_by!(language: SpecSeed.language, protocol: 'sms')

      expect(result).to eq(templates_created: 1, variants_created: 3)
      expect(template.template_id).to eq('user_create')
      expect(variant.text).to eq('Install body')
      expect(telegram.from).to be_nil
      expect(telegram.subject).to be_nil
      expect(telegram.text).to eq('Telegram body')
      expect(sms.from).to be_nil
      expect(sms.subject).to be_nil
      expect(sms.text).to eq('SMS body')
    end
  end

  it 'does not overwrite existing templates or variants' do
    template = NotificationTemplate.create!(
      name: 'spec_existing_template',
      label: 'Existing template',
      template_id: 'daily_report'
    )
    template.notification_template_variants.create!(
      language: SpecSeed.language,
      protocol: :email,
      from: 'custom@example.test',
      subject: 'Custom subject',
      text: 'Custom body'
    )

    Dir.mktmpdir do |dir|
      write_template(
        dir,
        'spec_existing_template',
        meta: <<~RUBY,
          template :user_create do
            label 'Changed template'
            protocol :email do
              from 'changed@example.test'
            end
          end
        RUBY
        text: 'Changed body'
      )

      result = described_class.install_defaults!(paths: [File.join(dir, 'templates')])
      template.reload
      variant = template.notification_template_variants.find_by!(language: SpecSeed.language, protocol: 'email')

      expect(result).to eq(templates_created: 0, variants_created: 2)
      expect(template.label).to eq('Existing template')
      expect(template.template_id).to eq('daily_report')
      expect(variant.from).to eq('custom@example.test')
      expect(variant.text).to eq('Custom body')
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
          end
        RUBY
        text: 'Default sender body'
      )

      variant = described_class.find_templates([File.join(dir, 'templates')]).first.variants.find { |v| v.protocol == 'email' }

      expect(variant.params).to include(
        from: 'support@example.test',
        reply_to: 'support@example.test',
        return_path: 'support@example.test'
      )
    end
  end

  it 'renders template times in the delivery user time zone' do
    NotificationTemplate.register :spec_time_zone_template, name: 'spec_time_zone_template'
    template = NotificationTemplate.create!(
      name: 'spec_time_zone_template',
      label: 'Spec time zone template',
      template_id: 'spec_time_zone_template'
    )
    template.notification_template_variants.create!(
      language: SpecSeed.language,
      protocol: :email,
      from: 'noreply@test.invalid',
      subject: 'At <%= local_time(@time, "%Y-%m-%d %H:%M %Z") %>',
      text: 'At <%= local_time(@time, "%Y-%m-%d %H:%M %Z") %>'
    )
    SpecSeed.user.update!(time_zone: 'America/New_York')

    mail = NotificationTemplate.send_email!(
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
      expect(template.variants.select { |v| v.protocol == 'email' }.map(&:lang)).to include('en')
      expect(template.variants.select { |v| v.protocol == 'telegram' }.map(&:lang)).to include('en')
      expect(template.variants.select { |v| v.protocol == 'sms' }.map(&:lang)).to include('en')
    end
  end

  it 'ships usable built-in template content' do
    templates = described_class.find_templates(described_class.default_template_paths)
    expect(templates).not_to be_empty

    templates.each do |template|
      variant = template.variants.detect { |v| v.protocol == 'email' && v.lang == 'en' }
      expect(variant).to be_present, "#{template.name} is missing English e-mail"
      telegram = template.variants.detect { |v| v.protocol == 'telegram' && v.lang == 'en' }
      expect(telegram).to be_present, "#{template.name} is missing English Telegram"
      sms = template.variants.detect { |v| v.protocol == 'sms' && v.lang == 'en' }
      expect(sms).to be_present, "#{template.name} is missing English SMS"

      params = variant.params
      expect(params[:subject]).to be_present
      expect(params[:text]).to be_present
      expect(telegram.params[:text]).to be_present
      expect(sms.params[:text]).to be_present

      [params[:subject], params[:text], params[:html], telegram.params[:text], sms.params[:text]].compact.each do |source|
        compile_erb(source)
      end

      content = [
        template.name,
        template.params[:label],
        params[:subject],
        params[:text],
        params[:html],
        telegram.params[:text],
        sms.params[:text]
      ].compact.join("\n")

      expect(content).not_to include('Template:')
      expect(content).not_to match(/vpsFree/i)
      expect(content).not_to match(/\bmember(ship|s)?\b/i)
    end
  end
end
