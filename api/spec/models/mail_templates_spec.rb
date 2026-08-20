# frozen_string_literal: true

require 'fileutils'
require 'tmpdir'
require 'erb'
require 'timeout'

RSpec.describe VpsAdmin::API::MailTemplates do
  before do
    SysConfig.where(
      category: 'notifications',
      name: 'template_source'
    ).load
  end

  def write_template(dir, name, meta:, plain:)
    path = File.join(dir, name)
    FileUtils.mkdir_p(File.join(path, 'email'))
    File.write(File.join(path, 'meta.rb'), meta)
    File.write(File.join(path, 'email', 'en.text.erb'), plain)
  end

  def compile_erb(source)
    RubyVM::InstructionSequence.compile(ERB.new(source, trim_mode: '-').src)
  end

  it 'loads email templates from notification template directories' do
    Dir.mktmpdir do |dir|
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
      variant = template.variants.first

      expect(described_class.send(:template_params, template)).to include(
        name: 'spec_directory_template',
        label: 'Directory template',
        template_id: 'user_create',
        user_visibility: 'default'
      )
      expect(described_class.send(:translation_params, template, variant)).to include(
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

  it 'creates and updates templates from the configured package' do
    template = MailTemplate.create!(
      name: 'spec_managed_template',
      label: 'Old managed template',
      template_id: 'daily_report'
    )
    template.mail_template_translations.create!(
      language: SpecSeed.language,
      from: 'old@example.test',
      subject: 'Old subject',
      text_plain: 'Old body'
    )

    Dir.mktmpdir do |dir|
      package_path = File.join(dir, 'package')
      templates_path = File.join(package_path, 'templates')
      write_template(
        templates_path,
        'spec_managed_template',
        meta: <<~RUBY,
          template :user_create do
            label 'Managed template'
            user_visibility true
            from 'managed@example.test'
            subject 'Managed subject'
          end
        RUBY
        plain: 'Managed body'
      )
      write_template(
        templates_path,
        'spec_managed_created',
        meta: <<~RUBY,
          template :user_create do
            label 'Created template'
            from 'created@example.test'
            subject 'Created subject'
          end
        RUBY
        plain: 'Created body'
      )

      result = described_class.reconcile!(
        path: package_path,
        source_id: 'managed-source-1'
      )

      template.reload
      translation = template.mail_template_translations.find_by!(language: SpecSeed.language)
      created = MailTemplate.find_by!(name: 'spec_managed_created')

      expect(result).to eq(
        source_id: 'managed-source-1',
        templates_created: 1,
        templates_updated: 1,
        translations_created: 1,
        translations_updated: 1
      )
      expect(template.label).to eq('Managed template')
      expect(template.template_id).to eq('user_create')
      expect(template.user_visibility).to eq('visible')
      expect(translation.from).to eq('managed@example.test')
      expect(translation.subject).to eq('Managed subject')
      expect(translation.text_plain).to eq('Managed body')
      expect(created.mail_template_translations.find_by!(language: SpecSeed.language).text_plain).to eq('Created body')
      expect(SysConfig.get('notifications', 'template_source')).to eq('managed-source-1')
    end
  end

  it 'repairs drift without writing unchanged templates' do
    Dir.mktmpdir do |dir|
      write_template(
        dir,
        'spec_managed_noop_template',
        meta: <<~RUBY,
          template :user_create do
            label 'Managed no-op template'
            from 'managed@example.test'
            subject 'Managed subject'
          end
        RUBY
        plain: 'Managed body'
      )

      described_class.reconcile!(path: dir, source_id: 'managed-source-1')

      template = MailTemplate.find_by!(name: 'spec_managed_noop_template')
      template.update!(label: 'Drifted label')

      expect do
        result = described_class.reconcile!(path: dir, source_id: 'managed-source-1')

        expect(result).to include(
          source_id: 'managed-source-1',
          templates_created: 0,
          templates_updated: 1,
          translations_created: 0,
          translations_updated: 0
        )
      end.to change(PaperTrail::Version, :count).by(1)

      expect do
        result = described_class.reconcile!(path: dir, source_id: 'managed-source-1')
        expect(result.values_at(:templates_updated, :translations_updated)).to eq([0, 0])
      end.not_to change(PaperTrail::Version, :count)
    end
  end

  it 'preserves templates and translations not present in the configured source' do
    unrelated = MailTemplate.create!(
      name: 'spec_unrelated_template',
      label: 'Unrelated template',
      template_id: 'daily_report'
    )
    translation = unrelated.mail_template_translations.create!(
      language: SpecSeed.language,
      from: 'unrelated@example.test',
      subject: 'Unrelated subject',
      text_plain: 'Unrelated body'
    )

    Dir.mktmpdir do |dir|
      write_template(
        dir,
        'spec_managed_other_template',
        meta: <<~RUBY,
          template :user_create do
            label 'Other template'
            from 'other@example.test'
            subject 'Other subject'
          end
        RUBY
        plain: 'Other body'
      )

      described_class.reconcile!(path: dir, source_id: 'managed-source-1')
    end

    expect(unrelated.reload).to have_attributes(
      label: 'Unrelated template',
      template_id: 'daily_report'
    )
    expect(translation.reload).to have_attributes(
      from: 'unrelated@example.test',
      subject: 'Unrelated subject',
      text_plain: 'Unrelated body'
    )
  end

  it 'rolls back template changes and the source marker when installation fails' do
    marker = SysConfig.create!(
      category: 'notifications',
      name: 'template_source',
      value: 'managed-source-old'
    )

    Dir.mktmpdir do |dir|
      write_template(
        dir,
        'spec_managed_good_template',
        meta: <<~RUBY,
          template :user_create do
            label 'Good template'
            from 'good@example.test'
            subject 'Good subject'
          end
        RUBY
        plain: 'Good body'
      )
      write_template(
        dir,
        'spec_managed_invalid_template',
        meta: <<~RUBY,
          template :user_create do
            label 'Second template'
            from 'invalid@example.test'
            subject 'Invalid subject'
          end
        RUBY
        plain: 'Invalid body'
      )

      allow(described_class).to receive(:reconcile_template!).and_wrap_original do |method, template, result|
        if template.name == 'spec_managed_invalid_template'
          invalid = MailTemplate.new
          invalid.errors.add(:base, 'injected reconciliation failure')
          raise ActiveRecord::RecordInvalid, invalid
        end

        method.call(template, result)
      end

      expect do
        described_class.reconcile!(path: dir, source_id: 'managed-source-new')
      end.to raise_error(ActiveRecord::RecordInvalid)
    end

    expect(MailTemplate.find_by(name: 'spec_managed_good_template')).to be_nil
    expect(marker.reload.value).to eq('managed-source-old')
  end

  it 'rejects missing source ids, paths and template content' do
    expect do
      described_class.reconcile!(path: '/path/that/does/not/exist', source_id: 'managed-source-1')
    end.to raise_error(VpsAdmin::API::NotificationTemplates::InvalidTemplate, /directory does not exist/)

    Dir.mktmpdir do |dir|
      expect do
        described_class.reconcile!(path: dir, source_id: 'managed-source-1')
      end.to raise_error(VpsAdmin::API::NotificationTemplates::InvalidTemplate, /no notification templates found/)
    end

    expect do
      described_class.reconcile!(path: Dir.tmpdir, source_id: ' ')
    end.to raise_error(ArgumentError, 'source_id is required')
  end

  it 'locks the source marker before updating it' do
    marker = SysConfig.create!(
      category: 'notifications',
      name: 'template_source',
      value: 'managed-source-1'
    )
    allow(SysConfig).to receive(:find_or_create_by!).and_return(marker)
    allow(marker).to receive(:lock!).and_call_original
    allow(marker).to receive(:value).and_call_original

    Dir.mktmpdir do |dir|
      write_template(
        dir,
        'spec_lock_template',
        meta: "template :user_create do\nend\n",
        plain: 'Lock body'
      )

      described_class.reconcile!(path: dir, source_id: 'managed-source-2')
    end

    expect(marker).to have_received(:lock!).ordered
    expect(marker).to have_received(:value).ordered
  end

  it 'recovers when another reconciler creates the source marker' do
    marker = SysConfig.create!(
      category: 'notifications',
      name: 'template_source',
      value: 'managed-source-1'
    )
    allow(SysConfig).to receive(:find_or_create_by!).and_raise(ActiveRecord::RecordNotUnique)
    allow(SysConfig).to receive(:find_by!).with(
      category: 'notifications',
      name: 'template_source'
    ).and_return(marker)

    expect(described_class.send(:source_marker!)).to eq(marker)
    expect(SysConfig).to have_received(:find_by!).with(
      category: 'notifications',
      name: 'template_source'
    )
  end

  it 'serializes concurrent reconciliations on separate database connections' do
    template_name = 'spec_managed_concurrent_template'
    source_id = 'managed-concurrent-source'
    marker_attempts = Queue.new
    install_started = Queue.new
    release_install = Queue.new
    connection_ids = Queue.new
    pause_lock = Mutex.new
    install_paused = false
    threads = []

    cleanup = proc do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          template_ids = MailTemplate.where(name: template_name).pluck(:id)
          translation_ids = MailTemplateTranslation.where(mail_template_id: template_ids).pluck(:id)

          PaperTrail::Version.where(
            item_type: 'MailTemplateTranslation',
            item_id: translation_ids
          ).delete_all
          PaperTrail::Version.where(
            item_type: 'MailTemplate',
            item_id: template_ids
          ).delete_all
          MailTemplateTranslation.where(id: translation_ids).delete_all
          MailTemplate.where(id: template_ids).delete_all
          SysConfig.where(
            category: 'notifications',
            name: 'template_source'
          ).delete_all
        end
      end.value
    end

    allow(described_class).to receive(:source_marker!).and_wrap_original do |method|
      marker_attempts << true
      method.call
    end
    allow(described_class).to receive(:reconcile_template!).and_wrap_original do |method, *args|
      pause = pause_lock.synchronize do
        next false if install_paused

        install_paused = true
      end

      if pause
        install_started << true
        release_install.pop
      end

      method.call(*args)
    end

    Dir.mktmpdir do |dir|
      write_template(
        dir,
        template_name,
        meta: <<~RUBY,
          template :user_create do
            label 'Concurrent managed template'
            from 'managed@example.test'
            subject 'Concurrent managed subject'
          end
        RUBY
        plain: 'Concurrent managed body'
      )

      install = proc do
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          connection_ids << connection.object_id
          described_class.reconcile!(path: dir, source_id:)
        end
      end

      threads << Thread.new(&install)
      Timeout.timeout(5) do
        marker_attempts.pop
        install_started.pop
      end

      threads << Thread.new(&install)
      Timeout.timeout(5) { marker_attempts.pop }
      expect(threads.last.join(0.1)).to be_nil

      release_install << true
      results = threads.map(&:value)

      expect(2.times.map { connection_ids.pop }.uniq.length).to eq(2)
      expect(results.sum { |result| result[:templates_created] }).to eq(1)
      expect(results.sum { |result| result[:translations_created] }).to eq(1)

      state = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          template = MailTemplate.find_by!(name: template_name)
          translation = template.mail_template_translations.find_by!(language: SpecSeed.language)

          {
            marker: SysConfig.get('notifications', 'template_source'),
            marker_count: SysConfig.where(
              category: 'notifications',
              name: 'template_source'
            ).count,
            template_count: MailTemplate.where(name: template_name).count,
            translation_count: template.mail_template_translations.count,
            body: translation.text_plain
          }
        end
      end.value

      expect(state).to eq(
        marker: source_id,
        marker_count: 1,
        template_count: 1,
        translation_count: 1,
        body: 'Concurrent managed body'
      )
    end
  ensure
    release_install << true
    threads.each { |thread| thread.join(5) }
    cleanup&.call
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

      template = described_class.find_templates([dir]).first
      variant = template.variants.first

      expect(described_class.send(:translation_params, template, variant)).to include(
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

  it 'uses only explicit recipients when exclusive delivery is requested' do
    MailTemplate.register :spec_exclusive_recipients
    template = MailTemplate.create!(
      name: 'spec_exclusive_recipients',
      label: 'Exclusive recipients',
      template_id: 'spec_exclusive_recipients'
    )
    template.mail_template_translations.create!(
      language: SpecSeed.language,
      from: 'noreply@test.invalid',
      subject: 'Security message',
      text_plain: 'Security message'
    )
    recipient = MailRecipient.create!(
      label: 'Global archive',
      to: 'archive@example.test',
      cc: 'audit@example.test',
      bcc: 'hidden@example.test'
    )
    MailTemplateRecipient.create!(mail_template: template, mail_recipient: recipient)

    mail = MailTemplate.send_mail!(
      :spec_exclusive_recipients,
      user: SpecSeed.user,
      to: ['primary@example.test'],
      exclusive_recipients: true
    )

    expect(mail.to).to eq('primary@example.test')
    expect(mail.cc).to eq('')
    expect(mail.bcc).to eq('')
  ensure
    MailTemplate.templates.delete(:spec_exclusive_recipients)
  end

  it 'ships directory-backed English templates for all registered defaults' do
    templates = described_class.find_templates(described_class.default_template_paths).to_h do |template|
      [template.name, template]
    end

    described_class.required_default_templates.each do |name, template_id|
      template = templates[name]

      expect(template).to be_present, "#{name} is missing"
      expect(template.id.to_s).to eq(template_id)
      expect(template.variants.map(&:language)).to include('en')
    end
  end

  it 'ships bilingual HTML password recovery messages' do
    template = described_class.find_templates(described_class.default_template_paths).find do |item|
      item.name == 'password_recovery'
    end
    translations = template.variants.index_by(&:language).transform_values do |variant|
      described_class.send(:translation_params, template, variant)
    end

    expect(translations.keys).to include('en', 'cs')
    expect(translations.fetch('en').fetch(:text_html)).to include(
      '>Set a new password</a>'
    )
    expect(translations.fetch('cs').fetch(:text_html)).to include(
      '>Nastavit nové heslo</a>'
    )
  end

  it 'ships bilingual plain password-change notifications' do
    template = described_class.find_templates(described_class.default_template_paths).find do |item|
      item.name == 'user_password_changed'
    end
    translations = template.variants.index_by(&:language).transform_values do |variant|
      described_class.send(:translation_params, template, variant)
    end

    expect(translations.keys).to include('en', 'cs')
    expect(translations.fetch('en').fetch(:text_plain)).to include(
      'The password for your vpsAdmin account was changed.'
    )
    expect(translations.fetch('cs').fetch(:text_plain)).to include(
      'heslo k Tvému účtu ve vpsAdminu bylo změněno.'
    )
    expect(translations.values.map { |translation| translation[:text_html] }).to all(be_nil)
  end

  it 'ships usable built-in template content' do
    templates = described_class.find_templates(described_class.default_template_paths)
    expect(templates).not_to be_empty

    templates.each do |template|
      variant = template.variants.detect { |item| item.language == 'en' }
      expect(variant).to be_present, "#{template.name} is missing English"

      params = described_class.send(:translation_params, template, variant)
      expect(params[:subject]).to be_present
      expect(params[:text_plain]).to be_present

      [params[:subject], params[:text_plain], params[:text_html]].compact.each do |source|
        compile_erb(source)
      end

      content = [
        template.name,
        described_class.send(:template_params, template)[:label],
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
