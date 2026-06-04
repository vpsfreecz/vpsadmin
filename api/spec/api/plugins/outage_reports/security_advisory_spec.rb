# frozen_string_literal: true

RSpec.describe 'VpsAdmin::API::Resources::Outage::SecurityAdvisory',
               requires_plugins: :outage_reports do
  include OutageReportsSpecHelpers

  before do
    header 'Accept', 'application/json'
    SpecSeed.admin
    SpecSeed.user
    SpecSeed.other_user
    SpecSeed.location
    SpecSeed.node
    SpecSeed.other_node
    SpecSeed.pool
    SpecSeed.other_pool
    SpecSeed.os_template
    SpecSeed.dns_resolver
  end

  def outage_security_advisory_index_path(outage_id)
    vpath("/outages/#{outage_id}/security_advisories")
  end

  def outage_security_advisory_path(outage_id, link_id)
    vpath("/outages/#{outage_id}/security_advisories/#{link_id}")
  end

  def json_get(path, params = nil)
    get path, params, {
      'CONTENT_TYPE' => 'application/json',
      'rack.input' => StringIO.new('{}')
    }
  end

  def json_post(path, payload)
    post path, JSON.dump(payload), { 'CONTENT_TYPE' => 'application/json' }
  end

  def json_delete(path)
    delete path, nil, { 'CONTENT_TYPE' => 'application/json' }
  end

  def outage_security_advisories
    json.dig('response', 'security_advisories') ||
      json.dig('response', 'outage_security_advisories') ||
      []
  end

  def outage_security_advisory_obj
    json.dig('response', 'security_advisory') ||
      json.dig('response', 'outage_security_advisory') ||
      json['response']
  end

  def expect_status(code)
    path = last_request&.path
    message = "Expected status #{code} for #{path}, got #{last_response.status} body=#{last_response.body}"
    expect(last_response.status).to eq(code), message
  end

  def build_outage(attrs = {})
    defaults = {
      begins_at: Time.utc(2026, 1, 1, 12, 0, 0),
      duration: 60,
      outage_type: :unplanned_outage,
      impact_type: :network,
      state: :announced,
      auto_resolve: true
    }
    create_outage_with_translation!(defaults.merge(attrs))
  end

  def build_advisory(attrs = {}, cves: 'CVE-2026-3000', **kwattrs)
    attrs = attrs.merge(kwattrs)

    advisory = ::SecurityAdvisory.create!(
      {
        state: :draft,
        name: 'Spec Vulnerability',
        created_by: SpecSeed.admin
      }.merge(attrs)
    )
    advisory.update_cves!(cves)
    advisory.security_advisory_translations.create!(
      language: SpecSeed.language,
      summary: 'Spec advisory summary',
      description: 'Spec advisory description',
      response: 'Spec mitigation response'
    )
    advisory.reload
  end

  def build_published_advisory
    build_advisory(
      state: :published,
      published_at: Time.utc(2026, 1, 1, 11, 0, 0),
      published_by: SpecSeed.admin
    )
  end

  describe 'API description' do
    it 'includes outage advisory link endpoints' do
      scopes = EndpointInventory.scopes_for_version(self, api_version)
      expect(scopes).to include(
        'outage.security_advisory#index',
        'outage.security_advisory#create',
        'outage.security_advisory#delete'
      )
    end
  end

  describe 'Outage links' do
    it 'hides draft advisory links from public outage output' do
      outage = build_outage
      draft = build_advisory
      published = build_published_advisory
      ::OutageSecurityAdvisory.create!(outage: outage, security_advisory: draft)
      public_link = ::OutageSecurityAdvisory.create!(outage: outage, security_advisory: published)

      json_get outage_security_advisory_index_path(outage.id)

      expect_status(200)
      expect(outage_security_advisories.map { |row| row['id'] }).to contain_exactly(public_link.id)

      as(SpecSeed.admin) { json_get outage_security_advisory_index_path(outage.id) }

      expect_status(200)
      expect(outage_security_advisories.map { |row| row['id'] }).to include(public_link.id)
    end

    it 'allows admins to create and remove outage links' do
      outage = build_outage
      advisory = build_published_advisory

      as(SpecSeed.admin) do
        json_post outage_security_advisory_index_path(outage.id), security_advisory: {
          security_advisory: advisory.id
        }
      end

      expect_status(200)
      expect(json['status']).to be(true)
      link_id = outage_security_advisory_obj.fetch('id')

      as(SpecSeed.admin) { json_delete outage_security_advisory_path(outage.id, link_id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(::OutageSecurityAdvisory.where(id: link_id)).to be_empty
    end
  end
end
