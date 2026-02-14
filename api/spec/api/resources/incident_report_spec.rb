# frozen_string_literal: true

RSpec.describe 'VpsAdmin::API::Resources::IncidentReport' do
  before do
    header 'Accept', 'application/json'
    SpecSeed.location
    SpecSeed.node
    SpecSeed.network_v4
    SpecSeed.os_template
    SpecSeed.admin
    SpecSeed.user
    SpecSeed.support
    SpecSeed.other_user
    seed
  end

  def index_path
    vpath('/incident_reports')
  end

  def show_path(id)
    vpath("/incident_reports/#{id}")
  end

  def json_get(path, params = nil)
    get path, params, {
      'CONTENT_TYPE' => 'application/json',
      'rack.input' => StringIO.new('{}')
    }
  end

  def json_post(path, payload)
    post path, JSON.dump(payload), {
      'CONTENT_TYPE' => 'application/json'
    }
  end

  def reports
    json.dig('response', 'incident_reports') || []
  end

  def report_obj
    json.dig('response', 'incident_report') || json['response']
  end

  def errors
    json.dig('response', 'errors') || json['errors'] || {}
  end

  def msg
    json['message'] || json.dig('response', 'message') || json['error']
  end

  def action_state_id
    json.dig('response', '_meta', 'action_state_id') || json.dig('_meta', 'action_state_id')
  end

  def report_ids
    reports.map { |row| row['id'] }
  end

  def resource_id(value)
    value.is_a?(Hash) ? value['id'] : value
  end

  def expect_status(code)
    path = last_request&.path
    message = "Expected status #{code} for #{path}, got #{last_response.status} body=#{last_response.body}"
    expect(last_response.status).to eq(code), message
  end

  def create_vps_row!(user:, node:, hostname:)
    vps = Vps.new(
      user_id: user.id,
      node_id: node.id,
      hostname: hostname,
      os_template_id: SpecSeed.os_template.id
    )

    vps.object_state =
      if Vps.respond_to?(:object_states) && Vps.object_states[:active]
        Vps.object_states[:active]
      else
        0
      end

    vps.save!(validate: false)
    vps
  end

  def create_ip!(network:, addr:)
    IpAddress.create!(
      network: network,
      ip_addr: addr,
      prefix: network.split_prefix,
      size: 1
    )
  end

  def create_assignment!(ip:, user:, vps:, from_date:)
    IpAddressAssignment.create!(
      ip_address: ip,
      ip_addr: ip.ip_addr,
      ip_prefix: ip.prefix,
      user: user,
      vps: vps,
      from_date: from_date
    )
  end

  def ensure_mailer_node!
    Node.find_or_create_by!(name: 'spec-mailer') do |n|
      n.location = SpecSeed.location
      n.role = :mailer
      n.ip_addr = '192.0.2.150'
      n.cpus = 1
      n.total_memory = 1024
      n.total_swap = 256
      n.active = true
    end
  end

  def ensure_mail_template_incident_report!
    template = MailTemplate.find_or_create_by!(name: 'vps_incident_report') do |tpl|
      tpl.label = 'Spec vps_incident_report'
      tpl.template_id = 'vps_incident_report'
      tpl.user_visibility = :default
    end

    return if template.mail_template_translations.where(language: SpecSeed.user.language).exists?

    template.mail_template_translations.create!(
      language: SpecSeed.user.language,
      from: 'noreply@example.test',
      subject: 'Spec incident report',
      text_plain: 'Spec incident report body'
    )
  end

  def create_mailbox!(label_suffix:)
    Mailbox.create!(
      label: "Spec mailbox #{label_suffix}",
      server: 'imap.example.test',
      port: 993,
      user: 'u',
      password: 'p',
      enable_ssl: true
    )
  end

  let(:seed) do
    base_time = Time.utc(2040, 1, 1, 12, 0, 0)
    vps_user = create_vps_row!(user: SpecSeed.user, node: SpecSeed.node, hostname: 'spec-user-vps')
    vps_other = create_vps_row!(user: SpecSeed.other_user, node: SpecSeed.node, hostname: 'spec-other-vps')
    ip_user = create_ip!(network: SpecSeed.network_v4, addr: '192.0.2.10')
    ip_other = create_ip!(network: SpecSeed.network_v4, addr: '192.0.2.11')
    assignment_user = create_assignment!(
      ip: ip_user,
      user: SpecSeed.user,
      vps: vps_user,
      from_date: base_time - (3 * 3600)
    )
    assignment_other = create_assignment!(
      ip: ip_other,
      user: SpecSeed.other_user,
      vps: vps_other,
      from_date: base_time - (3 * 3600)
    )
    mailbox_a = create_mailbox!(label_suffix: 'a')
    mailbox_b = create_mailbox!(label_suffix: 'b')

    user_incident_newer = IncidentReport.create!(
      user: SpecSeed.user,
      vps: vps_user,
      ip_address_assignment: assignment_user,
      filed_by: SpecSeed.admin,
      mailbox: mailbox_a,
      subject: 'Spec incident A',
      text: 'Spec text A',
      codename: 'code-a',
      detected_at: base_time - 3600,
      cpu_limit: nil,
      vps_action: :none
    )
    user_incident_older = IncidentReport.create!(
      user: SpecSeed.user,
      vps: vps_user,
      ip_address_assignment: assignment_user,
      filed_by: SpecSeed.admin,
      mailbox: mailbox_a,
      subject: 'Spec incident B',
      text: 'Spec text B',
      codename: 'code-b',
      detected_at: base_time - (2 * 3600),
      cpu_limit: nil,
      vps_action: :none
    )
    other_incident = IncidentReport.create!(
      user: SpecSeed.other_user,
      vps: vps_other,
      ip_address_assignment: assignment_other,
      filed_by: SpecSeed.admin,
      mailbox: mailbox_b,
      subject: 'Spec incident C',
      text: 'Spec text C',
      codename: 'code-other',
      detected_at: base_time - 1800,
      cpu_limit: nil,
      vps_action: :none
    )

    {
      vps_user: vps_user,
      vps_other: vps_other,
      assignment_user: assignment_user,
      assignment_other: assignment_other,
      user_incident_newer: user_incident_newer,
      user_incident_older: user_incident_older,
      other_incident: other_incident
    }
  end

  def vps_user
    seed.fetch(:vps_user)
  end

  def vps_other
    seed.fetch(:vps_other)
  end

  def assignment_user
    seed.fetch(:assignment_user)
  end

  def assignment_other
    seed.fetch(:assignment_other)
  end

  def user_incident_newer
    seed.fetch(:user_incident_newer)
  end

  def user_incident_older
    seed.fetch(:user_incident_older)
  end

  def other_incident
    seed.fetch(:other_incident)
  end

  describe 'API description' do
    it 'includes incident_report scopes' do
      scopes = EndpointInventory.scopes_for_version(self, api_version)
      expect(scopes).to include('incident_report#index', 'incident_report#show', 'incident_report#create')
    end
  end

  describe 'Index' do
    it 'rejects unauthenticated access' do
      json_get index_path

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'restricts normal users to their incidents with limited output' do
      as(SpecSeed.user) { json_get index_path }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(report_ids).to contain_exactly(user_incident_newer.id, user_incident_older.id)

      row = reports.find { |item| item['id'] == user_incident_newer.id }
      expect(row).not_to have_key('user')
      expect(row).not_to have_key('mailbox')
    end

    it 'restricts support users to their incidents' do
      as(SpecSeed.support) { json_get index_path }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(report_ids).to be_empty
    end

    it 'allows admins to see all incidents with user and mailbox fields' do
      as(SpecSeed.admin) { json_get index_path }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(report_ids).to contain_exactly(
        user_incident_newer.id,
        user_incident_older.id,
        other_incident.id
      )

      row = reports.find { |item| item['id'] == other_incident.id }
      expect(row).to have_key('user')
      expect(row).to have_key('mailbox')
      expect(resource_id(row['user'])).to eq(SpecSeed.other_user.id)
    end

    it 'orders by detected_at DESC' do
      as(SpecSeed.user) { json_get index_path }

      expect_status(200)
      expect(report_ids).to eq([user_incident_newer.id, user_incident_older.id])
    end

    it 'filters by codename' do
      as(SpecSeed.admin) { json_get index_path, incident_report: { codename: 'code-a' } }

      expect_status(200)
      expect(report_ids).to contain_exactly(user_incident_newer.id)
    end

    it 'filters by ip_addr without leaking other users' do
      as(SpecSeed.user) { json_get index_path, incident_report: { ip_addr: '192.0.2.10' } }

      expect_status(200)
      expect(report_ids).to contain_exactly(user_incident_newer.id, user_incident_older.id)

      as(SpecSeed.user) { json_get index_path, incident_report: { ip_addr: '192.0.2.11' } }

      expect_status(200)
      expect(report_ids).to be_empty

      as(SpecSeed.admin) { json_get index_path, incident_report: { ip_addr: '192.0.2.11' } }

      expect_status(200)
      expect(report_ids).to contain_exactly(other_incident.id)
    end

    it 'returns total_count meta when requested' do
      as(SpecSeed.admin) { json_get index_path, _meta: { count: true } }

      expect_status(200)
      expect(json.dig('response', '_meta', 'total_count')).to eq(IncidentReport.count)
    end
  end

  describe 'Show' do
    it 'rejects unauthenticated access' do
      json_get show_path(user_incident_newer.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows users to show their incident with limited output' do
      as(SpecSeed.user) { json_get show_path(user_incident_newer.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(report_obj['id']).to eq(user_incident_newer.id)
      expect(report_obj).not_to have_key('user')
      expect(report_obj).not_to have_key('mailbox')
    end

    it 'forbids users from showing other incidents' do
      as(SpecSeed.user) { json_get show_path(other_incident.id) }

      expect(last_response.status).to be_in([200, 403, 404])
      expect(json['status']).to be(false)
    end

    it 'allows admins to show any incident with user and mailbox fields' do
      as(SpecSeed.admin) { json_get show_path(other_incident.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(report_obj['id']).to eq(other_incident.id)
      expect(report_obj).to have_key('user')
      expect(report_obj).to have_key('mailbox')
    end

    it 'returns 404 for unknown incidents' do
      missing = IncidentReport.maximum(:id).to_i + 100
      as(SpecSeed.admin) { json_get show_path(missing) }

      expect(last_response.status).to be_in([200, 404])
      expect(json['status']).to be(false)
    end
  end

  describe 'Create' do
    let(:payload) do
      {
        vps: vps_user.id,
        ip_address_assignment: assignment_user.id,
        subject: 'Spec created incident',
        text: 'Spec created text',
        codename: 'code-created'
      }
    end

    before do
      ensure_mailer_node!
      ensure_mail_template_incident_report!
      ensure_signer_unlocked!
    end

    it 'rejects unauthenticated access' do
      json_post index_path, incident_report: payload

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(SpecSeed.user) { json_post index_path, incident_report: payload }

      expect(last_response.status).to be_in([200, 403])
      expect(json['status']).to be(false)
    end

    it 'allows admins to create with minimal payload' do
      expect do
        as(SpecSeed.admin) { json_post index_path, incident_report: payload }
      end.to change(IncidentReport, :count).by(1)

      expect_status(200)
      expect(json['status']).to be(true)
      expect(action_state_id.to_i).to be > 0
      expect(TransactionChain.find(action_state_id)).to be_present

      record = IncidentReport.find_by!(subject: payload[:subject])
      expect(record.text).to eq(payload[:text])
      expect(record.codename).to eq(payload[:codename])
      expect(record.vps_id).to eq(vps_user.id)
      expect(record.user_id).to eq(SpecSeed.user.id)
      expect(record.filed_by_id).to eq(SpecSeed.admin.id)
      expect(record.ip_address_assignment_id).to eq(assignment_user.id)
      expect(record.detected_at).not_to be_nil
    end

    it 'returns validation errors for missing vps' do
      as(SpecSeed.admin) { json_post index_path, incident_report: payload.except(:vps) }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(errors.keys.map(&:to_s)).to include('vps')
    end

    it 'returns validation errors for missing subject' do
      as(SpecSeed.admin) { json_post index_path, incident_report: payload.except(:subject) }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(errors.keys.map(&:to_s)).to include('subject')
    end

    it 'returns validation errors for missing text' do
      as(SpecSeed.admin) { json_post index_path, incident_report: payload.except(:text) }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(errors.keys.map(&:to_s)).to include('text')
    end

    it 'returns validation errors for invalid vps_action' do
      as(SpecSeed.admin) do
        json_post index_path, incident_report: payload.merge(vps_action: 'invalid')
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(errors.keys.map(&:to_s)).to include('vps_action')
    end
  end
end
