# frozen_string_literal: true

require 'json'

RSpec.describe ApiAppHelper do
  it 'responds to OPTIONS / with JSON' do
    header 'Accept', 'application/json'
    options '/'
    expect(last_response.status).to eq(200)
    expect(last_response.headers['Content-Type']).to include('application/json')

    body = JSON.parse(last_response.body)
    expect(body).to be_a(Hash)
    expect(body['response']).to be_a(Hash)
  end

  it 'localizes API self-description metadata' do
    header 'Accept', 'application/json'
    header 'Accept-Language', 'cs'
    options '/?describe=default'

    expect(last_response.status).to eq(200)

    body = JSON.parse(last_response.body)
    resources = body.dig('response', 'resources')
    expect(resources.dig('user', 'description')).to eq('Spravovat uživatele')
    expect(resources.dig('user', 'actions', 'touch', 'description'))
      .to eq('Aktualizovat poslední aktivitu')
    expect(resources.dig('user', 'actions', 'index', 'input', 'parameters', 'full_name', 'label'))
      .to eq('Celé jméno')
    expect(resources.dig('user', 'actions', 'index', 'input', 'parameters', 'full_name', 'description'))
      .to eq('Jméno a příjmení')
    expect(resources.dig('transaction_chain', 'actions', 'index', 'input', 'parameters', 'class_name', 'label'))
      .to eq('Název objektu')
  end

  it 'localizes keyed messages with interpolation' do
    ::I18n.with_locale(:cs) do
      expect(VpsAdmin::API::I18n.t('errors.resource_allocation_error', reason: 'pool full'))
        .to eq('Chyba alokace zdroje: pool full')
      expect(VpsAdmin::API::I18n.t('errors.resource_locked_by_transaction_chain', id: 42, label: 'test'))
        .to eq('Zdroj je uzamčen transakčním řetězcem 42 (test). Zkuste to prosím později.')
    end
  end

  it 'localizes route and host IP transaction labels as verbal nouns' do
    ::I18n.with_locale(:cs) do
      expect(VpsAdmin::API::I18n.t('transactions.labels.vps_route_add'))
        .to eq('Přidání routy')
      expect(VpsAdmin::API::I18n.t('transactions.labels.vps_route_del'))
        .to eq('Odebrání routy')
      expect(VpsAdmin::API::I18n.t('transactions.labels.netif_host_addr_add'))
        .to eq('Přidání host IP adresy')
      expect(VpsAdmin::API::I18n.t('transactions.labels.netif_host_addr_del'))
        .to eq('Odebrání host IP adresy')
    end
  end
end
