# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'requests plugin rake tasks', requires_plugins: :requests do # rubocop:disable RSpec/DescribeClass
  around do |example|
    with_rake_application do
      load_plugin_rake_tasks('plugins/requests/api/tasks/requests.rake')
      with_current_context(user: SpecSeed.admin) { example.run }
    end
  end

  let(:ipqs) { instance_double(VpsAdmin::API::Plugins::Requests::IPQS) }

  before do
    allow(VpsAdmin::API::Plugins::Requests::IPQS).to receive(:new).and_return(ipqs)
  end

  it 'persists successful registration IP checks' do
    req = build_registration_request!(
      api_ip_addr: '203.0.113.8',
      client_ip_addr: '198.51.100.8'
    )

    allow(ipqs).to receive(:check_ip).with('198.51.100.8').and_return(
      ipqs_response(
        success: true,
        request_id: 'ip-1',
        proxy: false,
        crawler: true,
        recent_abuse: false,
        vpn: true,
        tor: false,
        fraud_score: 42
      )
    )

    invoke_rake_task('vpsadmin:requests:check_registration_ips')

    req.reload
    expect(req.ip_checked).to be(true)
    expect(req.ip_success).to be(true)
    expect(req.ip_request_id).to eq('ip-1')
    expect(req.ip_proxy).to be(false)
    expect(req.ip_crawler).to be(true)
    expect(req.ip_recent_abuse).to be(false)
    expect(req.ip_vpn).to be(true)
    expect(req.ip_tor).to be(false)
    expect(req.ip_fraud_score).to eq(42)
  end

  it 'persists failed registration IP checks and skips ineligible requests' do
    checked = build_registration_request!(
      api_ip_addr: '203.0.113.9',
      client_ip_addr: '198.51.100.9',
      ip_checked: true
    )
    without_ip = build_registration_request!
    target = build_registration_request!(
      api_ip_addr: '203.0.113.10',
      client_ip_addr: '198.51.100.10'
    )

    allow(ipqs).to receive(:check_ip).with('198.51.100.10').and_return(
      ipqs_response(
        success: false,
        request_id: 'ip-fail',
        message: 'bad ip',
        errors: %w[one two]
      )
    )

    invoke_rake_task('vpsadmin:requests:check_registration_ips')

    expect(ipqs).to have_received(:check_ip).once
    expect(checked.reload.ip_success).to be_nil
    expect(without_ip.reload.ip_checked).to be_nil

    target.reload
    expect(target.ip_checked).to be(true)
    expect(target.ip_success).to be(false)
    expect(target.ip_request_id).to eq('ip-fail')
    expect(target.ip_message).to eq('bad ip')
    expect(target.ip_errors).to eq('one; two')
  end

  it 'persists successful mail checks including all flags' do
    req = build_registration_request!

    allow(ipqs).to receive(:check_mail).with(req.email).and_return(
      ipqs_response(
        success: true,
        request_id: 'mail-1',
        valid: true,
        disposable: false,
        timed_out: false,
        deliverability: 'high',
        catch_all: false,
        leaked: true,
        suspect: false,
        smtp_score: 9,
        overall_score: 8,
        fraud_score: 5,
        dns_valid: true,
        honeypot: false,
        spam_trap_score: 'none',
        recent_abuse: false,
        frequent_complainer: true
      )
    )

    invoke_rake_task('vpsadmin:requests:check_registration_mails')

    req.reload
    expect(req.mail_checked).to be(true)
    expect(req.mail_success).to be(true)
    expect(req.mail_request_id).to eq('mail-1')
    expect(req.mail_valid).to be(true)
    expect(req.mail_disposable).to be(false)
    expect(req.mail_timed_out).to be(false)
    expect(req.mail_deliverability).to eq('high')
    expect(req.mail_catch_all).to be(false)
    expect(req.mail_leaked).to be(true)
    expect(req.mail_suspect).to be(false)
    expect(req.mail_smtp_score).to eq(9)
    expect(req.mail_overall_score).to eq(8)
    expect(req.mail_fraud_score).to eq(5)
    expect(req.mail_dns_valid).to be(true)
    expect(req.mail_honeypot).to be(false)
    expect(req.mail_spam_trap_score).to eq('none')
    expect(req.mail_recent_abuse).to be(false)
    expect(req.mail_frequent_complainer).to be(true)
  end

  it 'persists failed mail checks and skips already checked requests' do
    checked = build_registration_request!(mail_checked: true)
    target = build_registration_request!(email: 'mail-fail@test.invalid')

    allow(ipqs).to receive(:check_mail).with(target.email).and_return(
      ipqs_response(
        success: false,
        request_id: 'mail-fail',
        message: 'bad mail',
        errors: ['blocked']
      )
    )

    invoke_rake_task('vpsadmin:requests:check_registration_mails')

    expect(ipqs).to have_received(:check_mail).once
    expect(checked.reload.mail_success).to be_nil

    target.reload
    expect(target.mail_checked).to be(true)
    expect(target.mail_success).to be(false)
    expect(target.mail_request_id).to eq('mail-fail')
    expect(target.mail_message).to eq('bad mail')
    expect(target.mail_errors).to eq('blocked')
  end

  it 'runs both registration check subtasks' do
    req = build_registration_request!(
      api_ip_addr: '203.0.113.11',
      client_ip_addr: '198.51.100.11'
    )

    allow(ipqs).to receive_messages(
      check_ip: ipqs_response(success: true, request_id: 'ip-2'),
      check_mail: ipqs_response(success: true, request_id: 'mail-2')
    )

    invoke_rake_task('vpsadmin:requests:check_registrations')

    expect(ipqs).to have_received(:check_ip).with('198.51.100.11')
    expect(ipqs).to have_received(:check_mail).with(req.email)
  end
end
