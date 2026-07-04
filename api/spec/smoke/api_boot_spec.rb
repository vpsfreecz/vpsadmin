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
  end

  it 'localizes keyed messages with interpolation' do
    ::I18n.with_locale(:cs) do
      expect(VpsAdmin::API::I18n.t('errors.resource_allocation_error', reason: 'pool full'))
        .to eq('Chyba alokace zdroje: pool full')
      expect(VpsAdmin::API::I18n.t('errors.resource_locked_by_transaction_chain', id: 42, label: 'test'))
        .to eq('Zdroj je uzamčen transakčním řetězcem 42 (test). Zkuste to prosím později.')
    end
  end
end
