require 'spec_helper'
require 'timeout'

RSpec.describe IpReleaseCampaign do
  let(:committed) { {} }

  before { unlock_transaction_signer! }

  # These fixtures are committed on independent connections; the normal example
  # transaction cannot make its writes visible to competing database sessions.
  def connection_thread(&block)
    Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        with_current_context do |session|
          block.call
        ensure
          session.destroy!
        end
      end
    end
  end

  def setup_campaign
    connection_thread do
      config = SpecSeed.user.environment_user_configs.find_by!(environment: SpecSeed.environment)
      committed[:config_id] = config.id
      committed[:uses] = ClusterResourceUse.where(class_name: 'EnvironmentUserConfig', row_id: config.id).map(&:attributes)
      ip = create_ip_address!(user: SpecSeed.user, addr: '192.0.2.249')
      ip.update!(charged_environment: SpecSeed.environment)
      committed[:ip_id] = ip.id
      campaign = described_class.create_selected!(ids: [ip.id], actor: SpecSeed.admin,
                                                  label: 'Concurrent release', deadline: Time.now + 604_800)
      committed[:campaign_id] = campaign.id
      committed[:request_id] = campaign.ip_release_requests.first.id
      committed[:item_id] = campaign.ip_release_request_addresses.first.id
      config.reload.ipv4
    end.value
  end

  after do
    connection_thread do
      DnsZoneTransfer.where(dns_zone_id: committed[:zone_id]).delete_all if committed[:zone_id]
      DnsZone.where(id: committed[:zone_id]).delete_all if committed[:zone_id]
      ResourceLock.where(resource: 'IpAddress', row_id: committed[:ip_id]).delete_all if committed[:ip_id]
      HostIpAddress.where(ip_address_id: committed[:ip_id]).delete_all if committed[:ip_id]
      IpAddress.where(id: committed[:ip_id]).delete_all
      NetworkInterface.where(id: committed[:netif_id]).delete_all if committed[:netif_id]
      IpReleaseRequestAddress.where(id: committed[:item_id]).delete_all
      IpReleaseRequest.where(id: committed[:request_id]).delete_all
      described_class.where(id: committed[:campaign_id]).delete_all
      if committed[:uses]
        ClusterResourceUse.where(class_name: 'EnvironmentUserConfig', row_id: committed[:config_id])
                          .where.not(id: committed[:uses].map { |attrs| attrs['id'] }).delete_all
        committed[:uses].each { |attrs| ClusterResourceUse.where(id: attrs['id']).update_all(attrs) }
      end
      { 'IpAddress' => committed[:ip_id], 'IpReleaseCampaign' => committed[:campaign_id],
        'DnsZone' => committed[:zone_id], 'DnsZoneTransfer' => committed[:transfer_id],
        'IpReleaseRequest' => committed[:request_id], 'IpReleaseRequestAddress' => committed[:item_id] }.each do |type, id|
        PaperTrail::Version.where(item_type: type, item_id: id).delete_all if id
      end
    end.value
  end

  it 'does not disown an IP while an assignment commits on another connection' do
    setup_campaign
    locked = Queue.new
    resume = Queue.new
    workers = []
    workers << connection_thread do
      IpAddress.transaction do
        ip = IpAddress.find(committed[:ip_id])
        ip.acquire_lock do
          ip.lock!
          locked << true
          resume.pop
          # This is the same IP lock protocol used by AddRoute. An interface
          # without a VPS also represents addresses held by export interfaces.
          netif = NetworkInterface.create!(name: 'release-race', kind: :veth_routed, max_tx: 0, max_rx: 0)
          committed[:netif_id] = netif.id
          ip.update!(network_interface: netif)
        end
      end
    end
    Timeout.timeout(10) { locked.pop }
    workers << connection_thread do
      described_class.find(committed[:campaign_id]).release!(actor: SpecSeed.admin)
    end
    expect(workers.last.join(0.1)).to be_nil
    resume << true
    Timeout.timeout(20) { workers.each(&:value) }
    connection_thread do
      expect(IpAddress.find(committed[:ip_id]).user_id).to eq(SpecSeed.user.id)
      expect(IpReleaseRequestAddress.find(committed[:item_id]).released_at).to be_nil
    end.value
  ensure
    resume << true if resume
    workers&.each { |thread| thread.join(25) || thread.kill.join }
  end

  it 'excludes an IP whose owner changes while release waits for its row lock' do
    setup_campaign
    locked = Queue.new
    resume = Queue.new
    workers = []
    workers << connection_thread do
      IpAddress.transaction do
        ip = IpAddress.find(committed[:ip_id])
        ip.acquire_lock do
          ip.lock!
          locked << true
          resume.pop
          ip.update!(user: SpecSeed.other_user)
        end
      end
    end
    Timeout.timeout(10) { locked.pop }
    workers << connection_thread do
      described_class.find(committed[:campaign_id]).release!(actor: SpecSeed.admin)
    end
    expect(workers.last.join(0.1)).to be_nil
    resume << true
    Timeout.timeout(20) { workers.each(&:value) }
    connection_thread do
      expect(IpAddress.find(committed[:ip_id]).user_id).to eq(SpecSeed.other_user.id)
      entry = IpReleaseRequestAddress.find(committed[:item_id])
      expect(entry.exclusion_reason).to eq('owner_changed')
      expect(entry.active_ip_address_id).to be_nil
      expect(entry.released_at).to be_nil
    end.value
  ensure
    resume << true if resume
    workers&.each { |thread| thread.join(25) || thread.kill.join }
  end

  it 'does not release while a user lifecycle change owns the user resource lock' do
    setup_campaign
    locked = Queue.new
    resume = Queue.new
    worker = connection_thread do
      User.unscoped.find(SpecSeed.user.id).acquire_lock do
        locked << true
        resume.pop
      end
    end
    Timeout.timeout(10) { locked.pop }
    connection_thread do
      described_class.find(committed[:campaign_id]).release!(actor: SpecSeed.admin)
      expect(IpAddress.find(committed[:ip_id]).user_id).to eq(SpecSeed.user.id)
      expect(IpReleaseRequestAddress.find(committed[:item_id]).last_result).to eq('failed')
    end.value
    resume << true
    Timeout.timeout(20) { worker.value }
  ensure
    resume << true if resume
    worker&.join(25) || worker&.kill&.join
  end

  it 'waits for a concurrent DNS transfer writer and cleans its newly committed grant' do
    setup_campaign
    connection_thread do
      committed[:zone_id] = create_dns_zone!(user: SpecSeed.user, source: :internal_source).id
    end.value
    locked = Queue.new
    resume = Queue.new
    workers = []
    workers << connection_thread do
      transfer = DnsZoneTransfer.new(dns_zone: DnsZone.find(committed[:zone_id]),
                                     host_ip_address: IpAddress.find(committed[:ip_id]).host_ip_addresses.first,
                                     peer_type: :secondary_type)
      first_save = true
      allow(transfer).to receive(:save!).and_wrap_original do |original, *args, **kwargs|
        if first_save
          first_save = false
          locked << true
          resume.pop
        end
        original.call(*args, **kwargs)
      end
      TransactionChains::DnsZoneTransfer::Create.fire(transfer)
      committed[:transfer_id] = transfer.id
    end
    Timeout.timeout(10) { locked.pop }
    workers << connection_thread do
      # Roll back only the release side after inspecting its queued cleanup so
      # the asynchronous chain and node fixtures cannot escape this example.
      described_class.transaction do
        ensure_available_node_status!(SpecSeed.node)
        described_class.find(committed[:campaign_id]).release!(actor: SpecSeed.admin)
        result = IpReleaseRequestAddress.find(committed[:item_id])
        expect(result.last_result).to eq('releasing'), result.last_error
        ip = IpAddress.find(committed[:ip_id])
        expect(ip.user_id).to eq(SpecSeed.user.id)
        expect(ip).to be_locked
        expect(DnsZoneTransfer.existing.where(dns_zone_id: committed[:zone_id])).to be_empty
        expect(result.cleanup_state).to eq('queued')
        raise ActiveRecord::Rollback
      end
    end
    expect(workers.last.join(0.1)).to be_nil
    resume << true
    Timeout.timeout(20) { workers.each(&:value) }
  ensure
    resume << true if resume
    workers&.each { |thread| thread.join(25) || thread.kill.join }
  end

  it 'applies relative quota changes to current data despite an older transaction snapshot' do
    before_usage = setup_campaign
    snapshot = Queue.new
    resume = Queue.new
    worker = connection_thread do
      EnvironmentUserConfig.transaction do
        config = EnvironmentUserConfig.find(committed[:config_id])
        config.ipv4 # Establish an older REPEATABLE READ snapshot.
        snapshot << true
        resume.pop
        config.reallocate_resource!(:ipv4, delta: 1, user: SpecSeed.user, save: true)
      end
    end
    Timeout.timeout(10) { snapshot.pop }
    connection_thread do
      described_class.find(committed[:campaign_id]).release!(actor: SpecSeed.admin)
    end.value
    resume << true
    Timeout.timeout(20) { worker.value }
    connection_thread do
      expect(EnvironmentUserConfig.find(committed[:config_id]).ipv4).to eq(before_usage)
    end.value
  ensure
    resume << true if resume
    worker&.join(25) || worker&.kill&.join
  end

  %i[keep exemption policy close release].each do |action|
    it "serializes release after a concurrent #{action} and reloads the current state" do
      before_usage = setup_campaign
      locked = Queue.new
      resume = Queue.new
      attempted = Queue.new
      workers = []
      workers << connection_thread do
        campaign = described_class.find(committed[:campaign_id])
        campaign.with_lock do
          locked << true
          resume.pop
          case action
          when :keep
            campaign.ip_release_requests.first.keep!(ids: [committed[:item_id]], reason: 'Migration', actor: SpecSeed.user)
          when :exemption
            campaign.ip_release_request_addresses.first.exempt!(reason: 'Reservation', actor: SpecSeed.admin)
          when :policy
            campaign.ip_release_requests.first.keep!(ids: [committed[:item_id]], reason: 'Migration', actor: SpecSeed.user)
            campaign.edit!({ allow_keep: false }, actor: SpecSeed.admin)
          when :close
            campaign.close!(actor: SpecSeed.admin)
          when :release
            campaign.release!(actor: SpecSeed.admin)
          end
        end
      end
      Timeout.timeout(10) { locked.pop }
      workers << connection_thread do
        campaign = described_class.find(committed[:campaign_id])
        attempted << true
        begin
          campaign.release!(actor: SpecSeed.admin)
        rescue IpReleaseCampaign::Error => e
          raise unless action == :close && e.message == 'closed'
        end
      end
      Timeout.timeout(10) { attempted.pop }
      expect(workers.last.join(0.1)).to be_nil
      resume << true
      Timeout.timeout(20) { workers.each(&:value) }
      connection_thread do
        ip = IpAddress.find(committed[:ip_id])
        config = EnvironmentUserConfig.find(committed[:config_id])
        released = %i[policy release].include?(action)
        expect(ip.user_id).to eq(released ? nil : SpecSeed.user.id)
        expect(config.ipv4).to eq(before_usage - (released ? 1 : 0))
        expect(IpReleaseRequestAddress.find(committed[:item_id]).released_at.present?).to eq(released)
      end.value
    ensure
      resume << true if resume
      workers&.each { |thread| thread.join(25) || thread.kill.join }
    end
  end
end
