{
  adminUserId,
  node1Id,
}:
let
  base = import ../user/common.nix {
    inherit adminUserId node1Id;
  };
in
base
+ ''
  def setup_alerts_cluster(services, node)
    setup_user_lifecycle_cluster(services, node)
    wait_for_mailer_nodectld(services)
    ensure_operational_alert_templates(services)
  end

  def wait_for_mailer_nodectld(services)
    wait_until_block_succeeds(name: 'mailer nodectld running') do
      _, container_status = services.succeeds('nixos-container status mailer', timeout: 180)
      expect(container_status).to include('up')

      _, nodectld_status = services.succeeds(
        'nixos-container run mailer -- nodectl status',
        timeout: 180
      )
      expect(nodectld_status).to include('State: running')
      true
    end
  end

  def run_api_task(services, klass:, method:, env: {})
    assignments = env.map do |k, v|
      "ENV[#{k.to_s.inspect}] = #{v.to_s.inspect}"
    end.join("\n")

    services.api_ruby_json(code: <<~RUBY)
      #{api_session_prelude(admin_user_id)}
      #{assignments}

      before_chain_id = TransactionChain.maximum(:id).to_i
      #{klass}.new.public_send(#{method.to_s.inspect})
      chain_ids = TransactionChain.where('id > ?', before_chain_id).order(:id).pluck(:id)

      puts JSON.dump(ok: true, chain_ids: chain_ids)
    RUBY
  end

  def wait_for_task_chains_done(services, response, label:)
    response.fetch('chain_ids').each do |chain_id|
      final_state = wait_for_vps_chain_done(services, chain_id)
      details = chain_failure_details(services, chain_id)

      expect(final_state).to eq(services.class::CHAIN_STATES[:done]), {
        label: label,
        chain_id: chain_id,
        final_state: final_state,
        details: details
      }.inspect
    end
  end

  def ensure_operational_alert_templates(services)
    services.api_ruby_json(code: <<~RUBY)
      %w[
        daily_report
        vps_incident_report
        vps_oom_report
        vps_oom_prevention
        vps_dataset_expanded
        vps_network_disabled
        vps_network_enabled
      ].each do |name|
        template = MailTemplate.find_or_create_by!(name: name) do |tpl|
          tpl.label = name.tr('_', ' ').capitalize
          tpl.template_id = name
        end

        next if template.mail_template_translations.where(language: Language.first).exists?

        template.mail_template_translations.create!(
          language: Language.first,
          from: 'noreply@test.invalid',
          subject: name + ' subject',
          text_plain: name + ' body'
        )
      end

      %w[user active vps active].each_slice(2) do |object, state|
        name = 'expiration_' + object + '_' + state
        template = MailTemplate.find_or_create_by!(name: name) do |tpl|
          tpl.label = name
          tpl.template_id = 'expiration_warning'
        end

        next if template.mail_template_translations.where(language: Language.first).exists?

        template.mail_template_translations.create!(
          language: Language.first,
          from: 'noreply@test.invalid',
          subject: name + ' subject',
          text_plain: name + ' body'
        )
      end

      daily_report = MailTemplate.find_by!(name: 'daily_report')
      recipient = MailRecipient.find_or_initialize_by(label: 'alerts daily report')
      recipient.assign_attributes(to: User.find(#{admin_user_id}).email)
      recipient.save! if recipient.changed?
      MailTemplateRecipient.find_or_create_by!(
        mail_template: daily_report,
        mail_recipient: recipient
      )

      puts JSON.dump(ok: true)
    RUBY
  end

  def create_alert_vps(services, hostname:, start: false)
    vps = create_vps(
      services,
      admin_user_id: admin_user_id,
      node_id: node1_id,
      hostname: hostname,
      start: start
    )

    wait_for_vps_on_node(
      services,
      vps_id: vps.fetch('id'),
      node_id: node1_id,
      running: true
    ) if start

    vps
  end

  def create_incident_report_row(services, vps_id:, action:)
    services.api_ruby_json(code: <<~RUBY)
      #{api_session_prelude(admin_user_id)}

      vps = Vps.find(#{Integer(vps_id)})
      location = vps.node.location
      network = Network.find_or_initialize_by(address: '198.51.100.0', prefix: 24)
      network.assign_attributes(
        label: 'Alerts Test Net',
        ip_version: 4,
        role: :private_access,
        managed: true,
        split_access: :no_access,
        split_prefix: 32,
        purpose: :vps,
        primary_location: network.primary_location || location
      )
      network.save! if network.changed?

      loc_net = LocationNetwork.find_or_initialize_by(location: location, network: network)
      loc_net.assign_attributes(
        primary: network.primary_location_id == location.id,
        priority: 10,
        autopick: true,
        userpick: true
      )
      loc_net.save! if loc_net.changed?

      octet = (IpAddress.maximum(:id).to_i % 200) + 20
      ip_addr = '198.51.100.' + octet.to_s
      while IpAddress.exists?(ip_addr: ip_addr)
        octet += 1
        ip_addr = '198.51.100.' + octet.to_s
      end

      ip = IpAddress.register(
        IPAddress.parse(ip_addr + '/' + network.split_prefix.to_s),
        network: network,
        user: nil,
        location: location,
        prefix: network.split_prefix,
        size: 1
      )

      assignment = IpAddressAssignment.create!(
        ip_address: ip,
        ip_addr: ip.ip_addr,
        ip_prefix: ip.prefix,
        user: vps.user,
        vps: vps,
        from_date: Time.now.utc - 3600
      )
      mailbox = Mailbox.create!(
        label: 'integration incident',
        server: 'imap.test.invalid',
        user: 'u',
        password: 'p'
      )
      incident = IncidentReport.create!(
        user: vps.user,
        filed_by: User.current,
        mailbox: mailbox,
        vps: vps,
        ip_address_assignment: assignment,
        subject: 'Integration incident',
        text: 'Incident body',
        detected_at: Time.now.utc,
        vps_action: #{action.to_s.inspect}
      )
      incident.update_column(:reported_at, nil)

      puts JSON.dump(id: incident.id)
    RUBY
  end

  def incident_report_row(services, incident_id)
    services.mysql_json_rows(sql: <<~SQL).first
      SELECT JSON_OBJECT(
        'id', id,
        'reported_at', reported_at
      )
      FROM incident_reports
      WHERE id = #{Integer(incident_id)}
      LIMIT 1
    SQL
  end

  def seed_oom_reports(services, vps_id:, count: 3, created_at: 'Time.now.utc')
    services.api_ruby_json(code: <<~RUBY)
      vps = Vps.find(#{Integer(vps_id)})
      ids = []
      #{Integer(count)}.times do |i|
        report = OomReport.create!(
          vps: vps,
          cgroup: '/integration/' + i.to_s,
          invoked_by_pid: 100 + i,
          invoked_by_name: 'ruby',
          killed_pid: 200 + i,
          killed_name: 'worker',
          count: i + 1,
          created_at: #{created_at},
          processed: true,
          ignored: false
        )
        ids << report.id
      end

      puts JSON.dump(ids: ids)
    RUBY
  end

  def oom_report_rows(services, ids)
    return [] if ids.empty?

    services.mysql_json_rows(sql: <<~SQL)
      SELECT JSON_OBJECT(
        'id', id,
        'reported_at', reported_at
      )
      FROM oom_reports
      WHERE id IN (#{ids.map { |id| Integer(id) }.join(',')})
      ORDER BY id
    SQL
  end

  def old_oom_report_count(services)
    services.mysql_scalar(sql: <<~SQL).to_i
      SELECT COUNT(*)
      FROM oom_reports
      WHERE created_at < DATE_SUB(NOW(), INTERVAL 1 DAY)
    SQL
  end

  def set_vps_expiration(services, vps_id:, expiration_sql:, remind_after_sql: 'nil')
    services.api_ruby_json(code: <<~RUBY)
      vps = Vps.find(#{Integer(vps_id)})
      vps.update!(
        expiration_date: #{expiration_sql},
        remind_after_date: #{remind_after_sql}
      )

      puts JSON.dump(id: vps.id)
    RUBY
  end

  def mail_log_count(services, template_name)
    services.mysql_scalar(sql: <<~SQL).to_i
      SELECT COUNT(*)
      FROM mail_logs ml
      INNER JOIN mail_templates mt ON mt.id = ml.mail_template_id
      WHERE mt.name = #{template_name.inspect}
    SQL
  end
''
