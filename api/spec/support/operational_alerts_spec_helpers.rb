# frozen_string_literal: true

require 'securerandom'

module OperationalAlertsSpecHelpers
  ALERT_TEMPLATES = %w[
    daily_report
    vps_incident_report
    vps_oom_report
    vps_oom_prevention
    vps_dataset_expanded
    user_failed_logins
    vps_network_disabled
    vps_network_enabled
    vps_resources_change
  ].freeze

  def with_env(vars)
    keys = vars.keys.map(&:to_s)
    saved = keys.to_h do |key|
      [key, ENV.has_key?(key) ? ENV[key] : :__missing__]
    end

    vars.each do |key, value|
      key = key.to_s
      value.nil? ? ENV.delete(key) : ENV[key] = value.to_s
    end

    yield
  ensure
    saved&.each do |key, value|
      value == :__missing__ ? ENV.delete(key) : ENV[key] = value
    end
  end

  def ensure_alert_mail_templates!
    ALERT_TEMPLATES.each do |template_name|
      ensure_mail_template!(template_name, template_name)
    end
  end

  def ensure_expiration_template!(object:, state:)
    name = "expiration_#{object}_#{state}"
    ensure_mail_template!(name, 'expiration_warning', label: "Expiration #{object} #{state}")
  end

  def ensure_mailer_available!
    ensure_available_node_status!(SpecSeed.node)
  end

  def create_mailbox_fixture!(label: nil)
    Mailbox.create!(
      label: label || "spec-mailbox-#{SecureRandom.hex(4)}",
      server: 'imap.test.invalid',
      port: 993,
      user: 'spec',
      password: 'secret',
      enable_ssl: true
    )
  end

  def create_mailbox_handler_fixture!(mailbox:, class_name:, order: 1, continue: false)
    MailboxHandler.create!(
      mailbox:,
      class_name:,
      order:,
      continue:
    )
  end

  def create_ip_assignment_fixture!(vps:, user: vps.user, ip_address: nil, from_date: 1.hour.ago,
                                    to_date: nil)
    netif = vps.network_interfaces.first || create_network_interface!(
      vps,
      name: "eth#{vps.network_interfaces.count}",
      kind: :veth_routed
    )
    ip_address ||= create_ip_address!(
      network: SpecSeed.network_v4,
      location: vps.node.location,
      user: nil,
      network_interface: netif
    )

    IpAddressAssignment.create!(
      ip_address:,
      ip_addr: ip_address.ip_addr,
      ip_prefix: ip_address.prefix,
      user:,
      vps:,
      from_date:,
      to_date:
    )
  end

  def create_incident_report_fixture!(user: SpecSeed.user, vps: nil, ip_address_assignment: nil,
                                      mailbox: nil, filed_by: SpecSeed.admin, subject: nil,
                                      text: 'Spec incident body', codename: nil,
                                      detected_at: Time.now.utc, cpu_limit: nil,
                                      vps_action: :none, reported_at: :default)
    fixture = nil
    unless vps
      fixture = build_standalone_vps_fixture(user:)
      vps = fixture.fetch(:vps)
    end

    ip_address_assignment ||= create_ip_assignment_fixture!(vps:, user:)
    mailbox ||= create_mailbox_fixture!

    incident = IncidentReport.create!(
      user:,
      filed_by:,
      mailbox:,
      vps:,
      ip_address_assignment:,
      subject: subject || "Spec incident #{SecureRandom.hex(4)}",
      text:,
      codename:,
      detected_at:,
      cpu_limit:,
      vps_action:
    )

    incident.update_column(:reported_at, reported_at) unless reported_at == :default

    fixture ? fixture.merge(incident:, ip_assignment: ip_address_assignment, mailbox:) : incident
  end

  def create_oom_report_fixture!(vps:, rule: nil, cgroup: '/', count: 1,
                                 created_at: Time.now.utc, reported_at: nil,
                                 processed: true, ignored: false,
                                 invoked_by_pid: 100, invoked_by_name: 'invoked',
                                 killed_pid: 200, killed_name: 'killed')
    OomReport.create!(
      vps:,
      cgroup:,
      invoked_by_pid:,
      invoked_by_name:,
      killed_pid:,
      killed_name:,
      count:,
      created_at:,
      reported_at:,
      processed:,
      ignored:,
      oom_report_rule: rule
    )
  end

  def build_oom_report_payload(vps:, cgroup: '/user.slice/spec.scope', count: 1,
                               time: Time.now.utc)
    {
      'vps_id' => vps.id,
      'cgroup' => cgroup,
      'count' => count,
      'time' => time.to_i,
      'invoked_by_pid' => 111,
      'invoked_by_name' => 'ruby',
      'killed_pid' => 222,
      'killed_name' => 'worker',
      'usage' => {
        'memory' => {
          'usage' => 1024,
          'limit' => 2048,
          'failcnt' => 3
        }
      },
      'stats' => {
        'cache' => 10,
        'rss' => 20
      },
      'tasks' => [
        {
          'pid' => 300,
          'vps_pid' => 30,
          'name' => 'worker',
          'uid' => 1000,
          'vps_uid' => 0,
          'tgid' => 300,
          'total_vm' => 4096,
          'rss' => 1024,
          'rss_anon' => 768,
          'rss_file' => 128,
          'rss_shmem' => 128,
          'pgtables_bytes' => 64,
          'swapents' => 0,
          'oom_score_adj' => 0
        }
      ]
    }
  end

  private

  def ensure_mail_template!(name, template_id, label: nil)
    template = MailTemplate.find_or_create_by!(name:) do |tpl|
      tpl.label = label || name.tr('_', ' ').capitalize
      tpl.template_id = template_id
    end

    return if template.mail_template_translations.where(language: SpecSeed.language).exists?

    template.mail_template_translations.create!(
      language: SpecSeed.language,
      from: 'noreply@test.invalid',
      subject: "#{name} subject",
      text_plain: "#{name} body"
    )
  end
end

RSpec.configure do |config|
  config.include OperationalAlertsSpecHelpers
end
