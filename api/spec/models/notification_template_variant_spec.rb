# frozen_string_literal: true

RSpec.describe NotificationTemplateVariant do
  def build_template(source, vars = {})
    described_class::TemplateBuilder.new(vars).build(source)
  end

  it 'renders safe HTML helpers' do
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
      reason: "**bold** <script>alert('x')</script>\n\n- item\n\n" \
              '[ok](https://example.test/?a=1&b=2)'
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
      html: VpsAdmin::API::NotificationTemplates::DEFAULT_TELEGRAM_HTML
    )

    vps_class = Struct.new(:id, :hostname, :cpu, :cpu_limit, :memory, :swap)
    user_class = Struct.new(:login)
    event_class = Struct.new(:event_type, :subject, :summary, :payload, :vps, :id)
    vps = vps_class.new(
      id: 123,
      hostname: 'spec-vps',
      cpu: 3,
      cpu_limit: nil,
      memory: 4096,
      swap: 256
    )
    admin = user_class.new(login: 'admin <user>')
    payload = {
      'cpu' => 3,
      'cpu_limit' => 0,
      'memory' => 4096,
      'swap' => 256
    }
    event = event_class.new(
      event_type: 'vps.resources_changed',
      subject: 'VPS #123 resources changed',
      summary: nil,
      payload:,
      vps:,
      id: 456
    )
    vars = {
      event:,
      notification_event: event,
      vps:,
      admin:,
      reason: 'scale up & test',
      payload:
    }

    rendered = NotificationTemplate.render_telegram!(
      :vps_resources_change,
      vars:
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
    rendered = NotificationTemplate.render_telegram!(:vps_resources_change, vars:)
    expect(rendered[:html]).to include('CPU: <code>3 cores, limit 250 %</code>')

    vps.cpu_limit = nil
    allow(VpsAdmin::API::Events).to receive(:webui_url).and_return(nil)
    rendered = NotificationTemplate.render_telegram!(:vps_resources_change, vars:)

    expect(rendered[:html]).to include('<b>VPS resources changed: spec-vps (#123)</b>')
    expect(rendered[:html]).not_to include('<a href=', 'Link:')
  end
end
