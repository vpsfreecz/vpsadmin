# frozen_string_literal: true

require 'securerandom'

RSpec.describe 'VpsAdmin::API::Resources::User' do
  before { header 'Accept', 'application/json' }

  def available_ips_path(id)
    vpath("/users/#{id}/available_ips")
  end

  def json_get(path, params = nil)
    get path, params, {
      'CONTENT_TYPE' => 'application/json',
      'rack.input' => StringIO.new('{}')
    }
  end

  def response_obj
    json.dig('response', 'available_ips') || json.dig('response', 'user') || json['response'] || {}
  end

  def response_message
    json['message'] || json.dig('response', 'message') || json['error']
  end

  def expect_status(code)
    path = last_request&.path
    message = "Expected status #{code} for #{path}, got #{last_response.status} body=#{last_response.body}"
    expect(last_response.status).to eq(code), message
  end

  def create_location!(label_prefix: 'Spec Location C')
    suffix = SecureRandom.hex(4)

    Location.create!(
      label: "#{label_prefix} #{suffix}",
      environment: SpecSeed.environment,
      domain: "spec-loc-c-#{suffix}.test",
      has_ipv6: true,
      remote_console_server: '',
      description: 'Spec Location C'
    )
  end

  def create_network_v4!(address:, primary_location:, label: nil, role: :public_access, purpose: :any)
    Network.create!(
      label: label || "Spec Net #{address}/24",
      address: address,
      prefix: 24,
      ip_version: 4,
      role: role,
      managed: true,
      split_access: :no_access,
      split_prefix: 32,
      purpose: purpose,
      primary_location: primary_location
    )
  end

  def create_location_network!(location:, network:, primary:, priority:, autopick:, userpick:)
    LocationNetwork.create!(
      location: location,
      network: network,
      primary: primary,
      priority: priority,
      autopick: autopick,
      userpick: userpick
    )
  end

  def create_ip!(addr:, network:, user:)
    IpAddress.create!(
      ip_addr: addr,
      prefix: network.split_prefix,
      size: 1,
      network: network,
      user: user
    )
  end

  describe 'API description' do
    it 'includes available_ips endpoint' do
      scopes = EndpointInventory.scopes_for_version(self, api_version)
      expect(scopes).to include('user#available_ips')
    end
  end

  describe 'AvailableIps' do
    it 'rejects unauthenticated access' do
      json_get available_ips_path(SpecSeed.user.id), user: { location: SpecSeed.location.id }

      expect(last_response.status).to be_in([401, 403])
      expect(json['status']).to be(false)
    end

    it 'forbids normal user querying a different user' do
      as(SpecSeed.user) do
        json_get available_ips_path(SpecSeed.other_user.id), user: { location: SpecSeed.location.id }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to include('access denied')
    end

    it 'counts user-owned free IPs and supports address_location' do
      vps_location = create_location!

      # Share SpecSeed.network_v4 between SpecSeed.location (primary) and vps_location
      create_location_network!(
        location: vps_location,
        network: SpecSeed.network_v4,
        primary: false,
        priority: 20,
        autopick: true,
        userpick: true
      )

      # Add one extra network available only in vps_location
      local_only_net = create_network_v4!(
        address: '198.51.100.0',
        primary_location: vps_location,
        label: 'Spec Net v4 local-only'
      )

      create_location_network!(
        location: vps_location,
        network: local_only_net,
        primary: true,
        priority: 5,
        autopick: true,
        userpick: true
      )

      # Two owned and free IPs: one on shared network, one on location-only network
      create_ip!(addr: '192.0.2.210', network: SpecSeed.network_v4, user: SpecSeed.user)
      create_ip!(addr: '198.51.100.10', network: local_only_net, user: SpecSeed.user)

      # Additional address owned by other user shouldn't be counted
      create_ip!(addr: '192.0.2.211', network: SpecSeed.network_v4, user: SpecSeed.other_user)

      # With address_location: only networks shared with the primary address location are usable
      as(SpecSeed.user) do
        json_get available_ips_path(SpecSeed.user.id), user: {
          location: vps_location.id,
          address_location: SpecSeed.location.id
        }
      end

      expect_status(200)
      expect(json['status']).to be(true)
      expect(response_obj['ipv4']).to eq(1)

      # Without address_location: any autopick networks in the VPS location are usable
      as(SpecSeed.user) do
        json_get available_ips_path(SpecSeed.user.id), user: { location: vps_location.id }
      end

      expect_status(200)
      expect(json['status']).to be(true)
      expect(response_obj['ipv4']).to eq(2)
    end

    it 'rejects address_location without shared networks' do
      vps_location = create_location!

      as(SpecSeed.user) do
        json_get available_ips_path(SpecSeed.user.id), user: {
          location: vps_location.id,
          address_location: SpecSeed.other_location.id
        }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to include('no shared networks')
    end
  end
end
