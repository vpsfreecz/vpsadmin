# frozen_string_literal: true

require 'fileutils'
require 'tmpdir'
require 'erb'
require 'timeout'

RSpec.describe VpsAdmin::API::NotificationTemplateReconciler do
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
      expect(described_class.send(:variant_params, template, variant)).to include(
        protocol: 'email',
        from: 'from@example.test',
        subject: 'Directory subject',
        text: 'Directory body'
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
            from 'from@example.test'
            subject 'Install subject'
          end
        RUBY
        plain: 'Install body'
      )

      result = described_class.install_defaults!(paths: [dir])

      template = NotificationTemplate.find_by!(name: 'spec_install_template')
      translation = template.notification_template_variants.find_by!(
        language: SpecSeed.language,
        protocol: :email
      )

      expect(result).to eq(
        templates_created: 1,
        variants_created: 1,
        variants_updated: 0
      )
      expect(template.template_id).to eq('user_create')
      expect(translation.text).to eq('Install body')
    end
  end

  it 'creates and updates templates from the configured package' do
    template = NotificationTemplate.create!(
      name: 'spec_managed_template',
      label: 'Old managed template',
      template_id: 'daily_report'
    )
    template.notification_template_variants.create!(
      language: SpecSeed.language,
      protocol: :email,
      from: 'old@example.test',
      subject: 'Old subject',
      text: 'Old body'
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
      translation = template.notification_template_variants.find_by!(
        language: SpecSeed.language,
        protocol: :email
      )
      created = NotificationTemplate.find_by!(name: 'spec_managed_created')

      expect(result).to eq(
        source_id: 'managed-source-1',
        templates_created: 1,
        templates_updated: 1,
        variants_created: 1,
        variants_updated: 1
      )
      expect(template.label).to eq('Managed template')
      expect(template.template_id).to eq('user_create')
      expect(template.user_visibility).to eq('visible')
      expect(translation.from).to eq('managed@example.test')
      expect(translation.subject).to eq('Managed subject')
      expect(translation.text).to eq('Managed body')
      expect(
        created.notification_template_variants.find_by!(
          language: SpecSeed.language,
          protocol: :email
        ).text
      ).to eq('Created body')
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

      template = NotificationTemplate.find_by!(name: 'spec_managed_noop_template')
      template.update!(label: 'Drifted label')

      expect do
        result = described_class.reconcile!(path: dir, source_id: 'managed-source-1')

        expect(result).to include(
          source_id: 'managed-source-1',
          templates_created: 0,
          templates_updated: 1,
          variants_created: 0,
          variants_updated: 0
        )
      end.to change(PaperTrail::Version, :count).by(1)

      expect do
        result = described_class.reconcile!(path: dir, source_id: 'managed-source-1')
        expect(result.values_at(:templates_updated, :variants_updated)).to eq([0, 0])
      end.not_to change(PaperTrail::Version, :count)
    end
  end

  it 'preserves templates and variants not present in the configured source' do
    unrelated = NotificationTemplate.create!(
      name: 'spec_unrelated_template',
      label: 'Unrelated template',
      template_id: 'daily_report'
    )
    translation = unrelated.notification_template_variants.create!(
      language: SpecSeed.language,
      protocol: :email,
      from: 'unrelated@example.test',
      subject: 'Unrelated subject',
      text: 'Unrelated body'
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
      text: 'Unrelated body'
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
          invalid = NotificationTemplate.new
          invalid.errors.add(:base, 'injected reconciliation failure')
          raise ActiveRecord::RecordInvalid, invalid
        end

        method.call(template, result)
      end

      expect do
        described_class.reconcile!(path: dir, source_id: 'managed-source-new')
      end.to raise_error(ActiveRecord::RecordInvalid)
    end

    expect(NotificationTemplate.find_by(name: 'spec_managed_good_template')).to be_nil
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
          template_ids = NotificationTemplate.where(name: template_name).pluck(:id)
          translation_ids = NotificationTemplateVariant.where(
            notification_template_id: template_ids
          ).pluck(:id)

          PaperTrail::Version.where(
            item_type: 'NotificationTemplateVariant',
            item_id: translation_ids
          ).delete_all
          PaperTrail::Version.where(
            item_type: 'NotificationTemplate',
            item_id: template_ids
          ).delete_all
          NotificationTemplateVariant.where(id: translation_ids).delete_all
          NotificationTemplate.where(id: template_ids).delete_all
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
      expect(results.sum { |result| result[:variants_created] }).to eq(1)

      state = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          template = NotificationTemplate.find_by!(name: template_name)
          translation = template.notification_template_variants.find_by!(
            language: SpecSeed.language,
            protocol: :email
          )

          {
            marker: SysConfig.get('notifications', 'template_source'),
            marker_count: SysConfig.where(
              category: 'notifications',
              name: 'template_source'
            ).count,
            template_count: NotificationTemplate.where(name: template_name).count,
            translation_count: template.notification_template_variants.count,
            body: translation.text
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
            from 'changed@example.test'
            subject 'Changed subject'
          end
        RUBY
        plain: 'Changed body'
      )

      result = described_class.install_defaults!(paths: [dir])
      template.reload
      translation = template.notification_template_variants.find_by!(
        language: SpecSeed.language,
        protocol: :email
      )

      expect(result).to eq(
        templates_created: 0,
        variants_created: 0,
        variants_updated: 0
      )
      expect(template.label).to eq('Existing template')
      expect(template.template_id).to eq('daily_report')
      expect(translation.from).to eq('custom@example.test')
      expect(translation.text).to eq('Custom body')
    end
  end

  it 'fills missing Telegram HTML when stored text matches packaged text' do
    template = NotificationTemplate.create!(
      name: 'spec_existing_telegram_template',
      label: 'Existing Telegram template',
      template_id: 'user_create'
    )
    template.notification_template_variants.create!(
      language: SpecSeed.language,
      protocol: :telegram,
      text: 'Packaged Telegram body'
    )

    Dir.mktmpdir do |dir|
      write_template(
        dir,
        'spec_existing_telegram_template',
        meta: "template :user_create do\nend\n",
        plain: 'E-mail body'
      )
      telegram_path = File.join(dir, 'spec_existing_telegram_template', 'telegram')
      FileUtils.mkdir_p(telegram_path)
      File.write(File.join(telegram_path, 'en.text.erb'), 'Packaged Telegram body')
      File.write(File.join(telegram_path, 'en.html.erb'), '<b>Packaged Telegram body</b>')

      result = described_class.install_defaults!(paths: [dir])
      variant = template.notification_template_variants.find_by!(
        language: SpecSeed.language,
        protocol: :telegram
      )

      expect(result).to eq(
        templates_created: 0,
        variants_created: 1,
        variants_updated: 1
      )
      expect(variant.text).to eq('Packaged Telegram body')
      expect(variant.html).to eq('<b>Packaged Telegram body</b>')
    end
  end

  it 'does not fill Telegram HTML when stored text was customized' do
    template = NotificationTemplate.create!(
      name: 'spec_custom_telegram_template',
      label: 'Custom Telegram template',
      template_id: 'user_create'
    )
    template.notification_template_variants.create!(
      language: SpecSeed.language,
      protocol: :telegram,
      text: 'Custom Telegram body'
    )

    Dir.mktmpdir do |dir|
      write_template(
        dir,
        'spec_custom_telegram_template',
        meta: "template :user_create do\nend\n",
        plain: 'E-mail body'
      )
      telegram_path = File.join(dir, 'spec_custom_telegram_template', 'telegram')
      FileUtils.mkdir_p(telegram_path)
      File.write(File.join(telegram_path, 'en.text.erb'), 'Packaged Telegram body')
      File.write(File.join(telegram_path, 'en.html.erb'), '<b>Packaged Telegram body</b>')

      result = described_class.install_defaults!(paths: [dir])
      variant = template.notification_template_variants.find_by!(
        language: SpecSeed.language,
        protocol: :telegram
      )

      expect(result).to eq(
        templates_created: 0,
        variants_created: 1,
        variants_updated: 0
      )
      expect(variant.text).to eq('Custom Telegram body')
      expect(variant.html).to be_nil
    end
  end

  it 'does not fill missing e-mail HTML in stored variants' do
    template = NotificationTemplate.create!(
      name: 'spec_existing_email_template',
      label: 'Existing e-mail template',
      template_id: 'user_create'
    )
    template.notification_template_variants.create!(
      language: SpecSeed.language,
      protocol: :email,
      from: 'custom@example.test',
      subject: 'Custom subject',
      text: 'Packaged e-mail body'
    )

    Dir.mktmpdir do |dir|
      write_template(
        dir,
        'spec_existing_email_template',
        meta: "template :user_create do\nend\n",
        plain: 'Packaged e-mail body'
      )
      File.write(
        File.join(dir, 'spec_existing_email_template', 'email', 'en.html.erb'),
        '<p>Packaged e-mail HTML</p>'
      )

      result = described_class.install_defaults!(paths: [dir])
      variant = template.notification_template_variants.find_by!(
        language: SpecSeed.language,
        protocol: :email
      )

      expect(result).to eq(
        templates_created: 0,
        variants_created: 0,
        variants_updated: 0
      )
      expect(variant.html).to be_nil
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

      expect(described_class.send(:variant_params, template, variant)).to include(
        protocol: 'email',
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
      subject: "At <%= local_time(@time, \"%Y-%m-%d %H:%M %Z\") %>\n",
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

    NotificationTemplate.register :spec_language_fallback_template, name: 'spec_language_fallback_template'
    template = NotificationTemplate.create!(
      name: 'spec_language_fallback_template',
      label: 'Spec language fallback template',
      template_id: 'spec_language_fallback_template'
    )
    template.notification_template_variants.create!(
      language: SpecSeed.language,
      protocol: :email,
      from: 'noreply@test.invalid',
      subject: 'English subject',
      text: 'English body'
    )
    template.notification_template_variants.create!(
      language: SpecSeed.language,
      protocol: :telegram,
      text: 'English Telegram body'
    )
    template.notification_template_variants.create!(
      language: SpecSeed.language,
      protocol: :sms,
      text: 'English SMS body'
    )

    mail = NotificationTemplate.send_email!(
      :spec_language_fallback_template,
      user:
    )
    telegram = NotificationTemplate.render_telegram!(
      :spec_language_fallback_template,
      user:
    )
    sms = NotificationTemplate.render_sms!(
      :spec_language_fallback_template,
      user:
    )

    expect(mail.subject).to eq('English subject')
    expect(mail.text_plain).to eq('English body')
    expect(telegram[:text]).to eq('English Telegram body')
    expect(sms[:text]).to eq('English SMS body')
    expect(
      VpsAdmin::API::Events.template_available?(
        :spec_language_fallback_template,
        nil,
        language,
        protocol: :telegram
      )
    ).to be(true)
  end

  it 'normalizes static e-mail subjects without template variables' do
    NotificationTemplate.register :spec_static_subject_template, name: 'spec_static_subject_template'
    template = NotificationTemplate.create!(
      name: 'spec_static_subject_template',
      label: 'Spec static subject template',
      template_id: 'spec_static_subject_template'
    )
    template.notification_template_variants.create!(
      language: SpecSeed.language,
      protocol: :email,
      from: 'noreply@test.invalid',
      subject: "Static subject\n",
      text: 'Static body'
    )

    mail = NotificationTemplate.send_email!(
      :spec_static_subject_template,
      user: SpecSeed.user
    )

    expect(mail.subject).to eq('Static subject')
  end

  it 'ships directory-backed English templates for all registered defaults' do
    templates = described_class.find_templates(described_class.default_template_paths).to_h do |template|
      [template.name, template]
    end

    described_class.required_default_templates.each do |name, template_id|
      template = templates[name]

      expect(template).to be_present, "#{name} is missing"
      expect(template.id.to_s).to eq(template_id)
      expect(
        template.variants.select { |variant| variant.protocol == 'email' }.map(&:language)
      ).to include('en')
      expect(
        template.variants.select { |variant| variant.protocol == 'telegram' }.map(&:language)
      ).to include('en')
      expect(
        template.variants.select { |variant| variant.protocol == 'sms' }.map(&:language)
      ).to include('en')
    end
  end

  it 'ships usable built-in template content' do
    templates = described_class.find_templates(described_class.default_template_paths)
    expect(templates).not_to be_empty

    templates.each do |template|
      variant = template.variants.detect do |item|
        item.protocol == 'email' && item.language == 'en'
      end
      telegram = template.variants.detect do |item|
        item.protocol == 'telegram' && item.language == 'en'
      end
      sms = template.variants.detect do |item|
        item.protocol == 'sms' && item.language == 'en'
      end
      expect(variant).to be_present, "#{template.name} is missing English e-mail"
      expect(telegram).to be_present, "#{template.name} is missing English Telegram"
      expect(sms).to be_present, "#{template.name} is missing English SMS"

      params = described_class.send(:variant_params, template, variant)
      expect(params[:subject]).to be_present
      expect(params[:text]).to be_present
      expect(telegram.content(:text)).to be_present
      expect(sms.content(:text)).to be_present

      sources = [
        params[:subject],
        params[:text],
        params[:html],
        telegram.content(:text),
        telegram.content(:html),
        sms.content(:text)
      ].compact
      sources.each do |source|
        compile_erb(source)
      end

      content = [
        template.name,
        described_class.send(:template_params, template)[:label],
        params[:subject],
        params[:text],
        params[:html],
        telegram.content(:text),
        telegram.content(:html),
        sms.content(:text)
      ].compact.join("\n")

      expect(content).not_to include('Template:')
      expect(content).not_to match(/vpsFree/i)
      expect(content).not_to match(/\bmember(ship|s)?\b/i)
    end
  end
end
