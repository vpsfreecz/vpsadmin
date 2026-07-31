# frozen_string_literal: true

require 'fileutils'
require 'tmpdir'
require 'erb'

RSpec.describe VpsAdmin::API::NotificationTemplates do
  def write_template(
    dir,
    name,
    meta:,
    text:,
    email_html: nil,
    telegram_text: nil,
    telegram_html: nil,
    sms_text: nil
  )
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
    File.write(File.join(email_path, 'en.html.erb'), email_html) if email_html
    File.write(File.join(telegram_path, 'en.text.erb'), telegram_text || 'Telegram body')
    File.write(File.join(telegram_path, 'en.html.erb'), telegram_html) if telegram_html
    File.write(File.join(sms_path, 'en.text.erb'), sms_text || 'SMS body')
    base
  end

  def compile_erb(source)
    RubyVM::InstructionSequence.compile(ERB.new(source, trim_mode: '-').src)
  end

  def build_template(source, vars = {})
    NotificationTemplateVariant::TemplateBuilder.new(vars).build(source)
  end

  it 'loads template package directories' do
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
        text: 'Directory body',
        telegram_html: '<b>Telegram body</b>'
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
        text: 'Telegram body',
        html: '<b>Telegram body</b>'
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

      expect(result).to eq(templates_created: 1, variants_created: 3, variants_updated: 0)
      expect(template.template_id).to eq('user_create')
      expect(variant.text).to eq('Install body')
      expect(telegram.from).to be_nil
      expect(telegram.subject).to be_nil
      expect(telegram.text).to eq('Telegram body')
      expect(telegram.html).to eq(described_class::DEFAULT_TELEGRAM_HTML)
      expect(sms.from).to be_nil
      expect(sms.subject).to be_nil
      expect(sms.text).to eq('SMS body')
    end
  end

  it 'creates and updates managed templates from source paths' do
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
      write_template(
        dir,
        'spec_managed_template',
        meta: <<~RUBY,
          template :user_create do
            label 'Managed template'
            user_visibility true
            protocol :email do
              from 'managed@example.test'
            end
          end
        RUBY
        text: 'Managed body',
        email_html: '<p>Managed HTML</p>',
        telegram_text: 'Managed Telegram body',
        telegram_html: '<b>Managed Telegram HTML</b>',
        sms_text: 'Managed SMS body'
      )

      result = described_class.install_managed!(
        paths: [dir],
        source_id: 'managed-source-1'
      )

      template.reload
      email = template.notification_template_variants.find_by!(
        language: SpecSeed.language,
        protocol: 'email'
      )
      telegram = template.notification_template_variants.find_by!(
        language: SpecSeed.language,
        protocol: 'telegram'
      )
      sms = template.notification_template_variants.find_by!(
        language: SpecSeed.language,
        protocol: 'sms'
      )

      expect(result).to eq(
        source_id: 'managed-source-1',
        unchanged_source: false,
        templates_created: 0,
        templates_updated: 1,
        variants_created: 2,
        variants_updated: 1
      )
      expect(template.label).to eq('Managed template')
      expect(template.template_id).to eq('user_create')
      expect(template.user_visibility).to eq('visible')
      expect(email.from).to eq('managed@example.test')
      expect(email.text).to eq('Managed body')
      expect(email.html).to eq('<p>Managed HTML</p>')
      expect(telegram.html).to eq('<b>Managed Telegram HTML</b>')
      expect(sms.text).to eq('Managed SMS body')
      expect(SysConfig.get('notifications', 'managed_templates_source_id')).to eq('managed-source-1')
    end
  end

  it 'skips managed template writes when the source id is unchanged' do
    SysConfig.create!(
      category: 'notifications',
      name: 'managed_templates_source_id',
      value: 'managed-source-1'
    )

    Dir.mktmpdir do |dir|
      write_template(
        dir,
        'spec_managed_noop_template',
        meta: <<~RUBY,
          template :user_create do
            label 'Managed no-op template'
          end
        RUBY
        text: 'Managed no-op body'
      )

      expect do
        result = described_class.install_managed!(
          paths: [File.join(dir, 'templates')],
          source_id: 'managed-source-1'
        )

        expect(result).to include(
          source_id: 'managed-source-1',
          unchanged_source: true,
          templates_created: 0,
          variants_created: 0
        )
      end.not_to change(NotificationTemplate, :count)
    end
  end

  it 'keeps default Telegram HTML safe for old template builders' do
    old_builder = Class.new do
      def build(source)
        ERB.new(source, trim_mode: '-').result(binding)
      end
    end.new

    expect(old_builder.build(described_class::DEFAULT_TELEGRAM_HTML)).to eq('')
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

      expect(result).to eq(templates_created: 0, variants_created: 2, variants_updated: 0)
      expect(template.label).to eq('Existing template')
      expect(template.template_id).to eq('daily_report')
      expect(variant.from).to eq('custom@example.test')
      expect(variant.text).to eq('Custom body')
    end
  end

  it 'fills missing Telegram HTML when existing text matches the packaged text' do
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
        meta: <<~RUBY,
          template :user_create do
            label 'Changed Telegram template'
          end
        RUBY
        text: 'Changed e-mail body',
        telegram_text: 'Packaged Telegram body',
        telegram_html: '<b>Changed Telegram HTML</b>'
      )

      result = described_class.install_defaults!(paths: [File.join(dir, 'templates')])
      template.reload
      variant = template.notification_template_variants.find_by!(
        language: SpecSeed.language,
        protocol: 'telegram'
      )

      expect(result).to eq(templates_created: 0, variants_created: 2, variants_updated: 1)
      expect(template.label).to eq('Existing Telegram template')
      expect(variant.text).to eq('Packaged Telegram body')
      expect(variant.html).to eq('<b>Changed Telegram HTML</b>')
    end
  end

  it 'does not fill missing Telegram HTML when existing text was customized' do
    template = NotificationTemplate.create!(
      name: 'spec_existing_telegram_template',
      label: 'Existing Telegram template',
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
        'spec_existing_telegram_template',
        meta: <<~RUBY,
          template :user_create do
            label 'Changed Telegram template'
          end
        RUBY
        text: 'Changed e-mail body',
        telegram_text: 'Changed Telegram body',
        telegram_html: '<b>Changed Telegram HTML</b>'
      )

      result = described_class.install_defaults!(paths: [File.join(dir, 'templates')])
      template.reload
      variant = template.notification_template_variants.find_by!(
        language: SpecSeed.language,
        protocol: 'telegram'
      )

      expect(result).to eq(templates_created: 0, variants_created: 2, variants_updated: 0)
      expect(template.label).to eq('Existing Telegram template')
      expect(variant.text).to eq('Custom Telegram body')
      expect(variant.html).to be_nil
    end
  end

  it 'does not fill missing e-mail HTML in existing variants' do
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
        meta: <<~RUBY,
          template :user_create do
            label 'Changed e-mail template'
          end
        RUBY
        text: 'Packaged e-mail body',
        email_html: '<p>Changed e-mail HTML</p>'
      )

      result = described_class.install_defaults!(paths: [File.join(dir, 'templates')])
      variant = template.notification_template_variants.find_by!(
        language: SpecSeed.language,
        protocol: 'email'
      )

      expect(result).to eq(templates_created: 0, variants_created: 2, variants_updated: 0)
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

    mail = NotificationTemplate.send_email!(
      :spec_language_fallback_template,
      user:
    )

    expect(mail.subject).to eq('English subject')
    expect(mail.text_plain).to eq('English body')
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

  it 'renders safe HTML helpers in template variants' do
    allow(VpsAdmin::API::Events).to receive(:webui_url).and_return('https://webui.example.test')

    expect(build_template('<%= h("<alert&>") %>')).to eq('&lt;alert&amp;&gt;')
    expect(build_template('<%= html_link("Open <x>", "https://example.test/?a=1&b=2") %>')).to eq(
      '<a href="https://example.test/?a=1&amp;b=2">Open &lt;x&gt;</a>'
    )
    expect(build_template('<%= webui_link("VPS #1", "?page=adminvps&action=info&veid=1") %>')).to eq(
      '<a href="https://webui.example.test/?page=adminvps&amp;action=info&amp;veid=1">VPS #1</a>'
    )
    markdown_reason = <<~MARKDOWN
      **bold** <script>alert("x")</script>

      [bad](javascript:alert(1)) [ok](https://example.test/?a=1&b=2)
    MARKDOWN
    rendered_email_reason = build_template(
      '<%= markdown_html(@reason) %>',
      reason: markdown_reason
    )
    expect(rendered_email_reason).to include('<strong>bold</strong>')
    expect(rendered_email_reason).not_to include('<script>', 'javascript:')

    rendered = build_template(
      '<%= markdown_telegram_html(@reason) %>',
      reason: "**bold** <script>alert('x')</script>\n\n- item\n\n[ok](https://example.test/?a=1&b=2)"
    )
    expect(rendered).to eq(
      "<strong>bold</strong> alert(&#39;x&#39;)\n\n" \
      "- item\n\n" \
      '<a href="https://example.test/?a=1&amp;b=2">ok</a>'
    )
    expect(rendered).not_to include('<p>', '<ul>', '<li>', 'script', 'javascript:')
  end

  it 'renders Telegram resource changes with linked VPS details and limits' do
    allow(VpsAdmin::API::Events).to receive(:webui_url).and_return('https://webui.example.test')
    template = NotificationTemplate.find_or_initialize_by(name: 'vps_resources_change')
    template.assign_attributes(
      label: 'VPS resources changed',
      template_id: 'vps_resources_change'
    )
    template.save!
    template.notification_template_variants.where(
      language: SpecSeed.language,
      protocol: :telegram
    ).delete_all
    template.notification_template_variants.create!(
      language: SpecSeed.language,
      protocol: :telegram,
      text: 'Plain fallback',
      html: described_class::DEFAULT_TELEGRAM_HTML
    )
    vps_class = Struct.new(:id, :hostname, :cpu, :cpu_limit, :memory, :swap)
    user_class = Struct.new(:login)
    event_class = Struct.new(:event_type, :subject, :summary, :parameters, :vps, :id)
    vps = vps_class.new(id: 123, hostname: 'spec-vps', cpu: 3, cpu_limit: nil, memory: 4096, swap: 256)
    admin = user_class.new(login: 'admin <user>')
    parameters = {
      'cpu' => 3,
      'cpu_limit' => 0,
      'memory' => 4096,
      'swap' => 256
    }
    event = event_class.new(
      event_type: 'vps.resources_changed',
      subject: 'VPS #123 resources changed',
      summary: nil,
      parameters:,
      vps:,
      id: 456
    )

    rendered = NotificationTemplate.render_telegram!(
      :vps_resources_change,
      vars: {
        event:,
        notification_event: event,
        vps:,
        admin:,
        reason: 'scale up & test',
        parameters:
      }
    )

    expect(rendered[:html]).to eq(
      '<b>VPS resources changed: ' \
      '<a href="https://webui.example.test/?page=adminvps&amp;action=info&amp;veid=123">' \
      "spec-vps (#123)</a></b>\n\n" \
      "<b>Current limits:</b>\n" \
      "CPU: <code>3 cores, limit 300 %</code>\n" \
      "Memory: <code>4096 MB</code>\n" \
      "Swap: <code>256 MB</code>\n\n" \
      "Reason: scale up &amp; test\n" \
      "Changed by: admin &lt;user&gt;\n\n" \
      'Link: <a href="https://webui.example.test/?page=adminvps&amp;action=info&amp;veid=123">VPS details</a>'
    )
    expect(rendered[:html]).not_to include('open in vpsAdmin')

    vps.cpu_limit = 250
    rendered = NotificationTemplate.render_telegram!(
      :vps_resources_change,
      vars: {
        event:,
        notification_event: event,
        vps:,
        admin:,
        reason: 'scale up & test',
        parameters:
      }
    )
    expect(rendered[:html]).to include('CPU: <code>3 cores, limit 250 %</code>')

    vps.cpu_limit = nil
    allow(VpsAdmin::API::Events).to receive(:webui_url).and_return(nil)

    rendered = NotificationTemplate.render_telegram!(
      :vps_resources_change,
      vars: {
        event:,
        notification_event: event,
        vps:,
        admin:,
        reason: 'scale up & test',
        parameters:
      }
    )

    expect(rendered[:html]).to include('<b>VPS resources changed: spec-vps (#123)</b>')
    expect(rendered[:html]).not_to include('<a href=')
    expect(rendered[:html]).not_to include('Link:')
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

      [
        params[:subject],
        params[:text],
        params[:html],
        telegram.params[:text],
        telegram.params[:html],
        sms.params[:text]
      ].compact.each do |source|
        compile_erb(source)
      end

      content = [
        template.name,
        template.params[:label],
        params[:subject],
        params[:text],
        params[:html],
        telegram.params[:text],
        telegram.params[:html],
        sms.params[:text]
      ].compact.join("\n")

      expect(content).not_to include('Template:')
      expect(content).not_to match(/vpsFree/i)
      expect(content).not_to match(/\bmember(ship|s)?\b/i)
    end
  end
end
