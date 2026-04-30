# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'payments plugin rake tasks', requires_plugins: :payments do # rubocop:disable RSpec/DescribeClass
  around do |example|
    with_rake_application do
      load_plugin_rake_tasks('plugins/payments/api/tasks/payments.rake')
      with_current_context(user: SpecSeed.admin) { example.run }
    end
  end

  it 'warns and exits when BACKEND is missing' do
    _out, err = capture_streams do
      expect do
        invoke_rake_task('vpsadmin:payments:fetch', env: { BACKEND: nil })
      end.to raise_error(SystemExit)
    end

    expect(err).to include('Specify which BACKEND to use')
  end

  it 'warns and exits when BACKEND is unknown' do
    allow(VpsAdmin::API::Plugins::Payments).to receive(:get_backend).and_return(nil)

    _out, err = capture_streams do
      expect do
        invoke_rake_task('vpsadmin:payments:fetch', env: { BACKEND: 'missing' })
      end.to raise_error(SystemExit)
    end

    expect(err).to include("BACKEND 'missing' not found")
  end

  it 'invokes the chosen backend' do
    backend = Object.new
    backend_class = Class.new
    allow(backend).to receive(:fetch)
    allow(backend_class).to receive(:new).and_return(backend)
    allow(VpsAdmin::API::Plugins::Payments).to receive(:get_backend)
      .with(:fio)
      .and_return(backend_class)

    invoke_rake_task('vpsadmin:payments:fetch', env: { BACKEND: 'fio' })

    expect(backend).to have_received(:fetch)
  end

  it 'delegates accepting payments to UserAccount' do
    allow(UserAccount).to receive(:accept_payments)

    invoke_rake_task('vpsadmin:payments:accept')

    expect(UserAccount).to have_received(:accept_payments)
  end

  it 'wires process as fetch followed by accept' do
    calls = []
    backend = Object.new
    backend_class = Class.new
    allow(backend).to receive(:fetch) { calls << :fetch }
    allow(backend_class).to receive(:new).and_return(backend)
    allow(UserAccount).to receive(:accept_payments) { calls << :accept_payments }
    allow(VpsAdmin::API::Plugins::Payments).to receive(:get_backend)
      .with(:fio)
      .and_return(backend_class)

    invoke_rake_task('vpsadmin:payments:process', env: { BACKEND: 'fio' })

    expect(calls).to eq(%i[fetch accept_payments])
  end

  it 'passes period and language from the environment to mail_overview' do
    allow(VpsAdmin::API::Plugins::Payments::TransactionChains::MailOverview).to receive(:fire)

    invoke_rake_task(
      'vpsadmin:payments:mail_overview',
      env: { PERIOD: '7200', VPSADMIN_LANG: SpecSeed.language.code }
    )

    expect(VpsAdmin::API::Plugins::Payments::TransactionChains::MailOverview)
      .to have_received(:fire).with(7200, SpecSeed.language)
  end

  it 'defaults mail_overview period and language' do
    allow(VpsAdmin::API::Plugins::Payments::TransactionChains::MailOverview).to receive(:fire)

    invoke_rake_task('vpsadmin:payments:mail_overview')

    expect(VpsAdmin::API::Plugins::Payments::TransactionChains::MailOverview)
      .to have_received(:fire).with(86_400, kind_of(Language))
  end
end
