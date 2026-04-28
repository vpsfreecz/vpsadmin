# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::Tasks::DatasetExpansion do
  around do |example|
    with_current_context(user: SpecSeed.admin) do
      example.run
    end
  end

  let(:task) { described_class.new }
  let(:user) { SpecSeed.user }

  before do
    stub_const("#{described_class}::MAX_OVER_REFQUOTA_SECONDS", 3600)
    stub_const("#{described_class}::COOLDOWN", 0)
    stub_const("#{described_class}::MAX_EXPANSIONS", 0)
    stub_const("#{described_class}::STRICT_MAX_EXPANSIONS", 99)
    stub_const("#{described_class}::OVERQUOTA_MB", 1)
    stub_const("#{described_class}::STRICT_OVERQUOTA_MB", 100_000)
    stub_const("#{described_class}::FREE_PERCENT", 5)
    stub_const("#{described_class}::FREE_MB", 1)
  end

  def create_expansion_event!(dataset:, added_space: 1024)
    DatasetExpansionEvent.create!(
      dataset: dataset,
      original_refquota: 10_240,
      added_space: added_space,
      new_refquota: 10_240 + added_space
    )
  end

  def set_referenced!(record, value)
    record.dataset_properties.find_by!(name: 'referenced').update!(value: value)
  end

  def set_vps_running!(vps, uptime: 7200)
    VpsCurrentStatus.find_or_initialize_by(vps: vps).tap do |status|
      status.status = true
      status.is_running = true
      status.uptime = uptime
      status.update_count = 1
      status.save!
    end
  end

  def active_expansion_fixture(**opts)
    fixture = build_active_dataset_expansion_fixture(user: user, **opts)
    fixture.fetch(:expansion).update!(stop_vps: true)
    fixture
  end

  describe '#process_events' do
    before do
      allow(TransactionChains::Mail::VpsDatasetExpanded).to receive(:fire)
    end

    it 'does nothing when ProcessEvent returns nil' do
      event = create_expansion_event!(dataset: build_standalone_vps_fixture(user: user).fetch(:dataset))
      allow(VpsAdmin::API::Operations::DatasetExpansion::ProcessEvent).to receive(:run).with(
        event,
        max_over_refquota_seconds: 3600
      ).and_return(nil)

      task.process_events

      expect(TransactionChains::Mail::VpsDatasetExpanded).not_to have_received(:fire)
    end

    it 'does not notify when notifications are disabled' do
      fixture = active_expansion_fixture(enable_notifications: false)
      create_expansion_event!(dataset: fixture.fetch(:dataset))
      allow(VpsAdmin::API::Operations::DatasetExpansion::ProcessEvent).to receive(:run).and_return(
        fixture.fetch(:expansion)
      )

      task.process_events

      expect(TransactionChains::Mail::VpsDatasetExpanded).not_to have_received(:fire)
    end

    it 'notifies each returned expansion only once' do
      fixture = active_expansion_fixture
      2.times { create_expansion_event!(dataset: fixture.fetch(:dataset)) }
      allow(VpsAdmin::API::Operations::DatasetExpansion::ProcessEvent).to receive(:run).and_return(
        fixture.fetch(:expansion)
      )

      task.process_events

      expect(TransactionChains::Mail::VpsDatasetExpanded).to have_received(:fire).once.with(
        fixture.fetch(:expansion)
      )
    end

    it 'does not notify inactive VPS expansions' do
      fixture = active_expansion_fixture
      fixture.fetch(:vps).update!(object_state: :suspended)
      create_expansion_event!(dataset: fixture.fetch(:dataset))
      allow(VpsAdmin::API::Operations::DatasetExpansion::ProcessEvent).to receive(:run).and_return(
        fixture.fetch(:expansion).reload
      )

      task.process_events

      expect(TransactionChains::Mail::VpsDatasetExpanded).not_to have_received(:fire)
    end

    it 'rescues locked resources and continues with later events' do
      locked_fixture = active_expansion_fixture
      ok_fixture = active_expansion_fixture
      locked_event = create_expansion_event!(dataset: locked_fixture.fetch(:dataset))
      ok_event = create_expansion_event!(dataset: ok_fixture.fetch(:dataset))
      allow(VpsAdmin::API::Operations::DatasetExpansion::ProcessEvent).to receive(:run) do |event, **_opts|
        raise ResourceLocked.new(event.dataset, 'locked') if event.id == locked_event.id

        ok_fixture.fetch(:expansion) if event.id == ok_event.id
      end

      expect { task.process_events }.to output(/Dataset id=#{locked_event.dataset_id} .* locked/).to_stderr
      expect(TransactionChains::Mail::VpsDatasetExpanded).to have_received(:fire).once.with(
        ok_fixture.fetch(:expansion)
      )
    end
  end

  describe '#stop_vps' do
    before do
      allow(TransactionChains::Vps::StopOverQuota).to receive(:fire)
    end

    it 'advances over-refquota seconds only while the dataset is over quota' do
      over = active_expansion_fixture
      under = active_expansion_fixture
      checked_at = 30.minutes.ago
      set_referenced!(over.fetch(:dataset), over.fetch(:expansion).original_refquota + 100)
      set_referenced!(under.fetch(:dataset), under.fetch(:expansion).original_refquota - 100)
      over.fetch(:expansion).update!(last_over_refquota_check: checked_at)
      under.fetch(:expansion).update!(last_over_refquota_check: checked_at)

      task.stop_vps

      expect(over.fetch(:expansion).reload.over_refquota_seconds).to be > 0
      expect(under.fetch(:expansion).reload.over_refquota_seconds).to eq(0)
    end

    it 'suspends VPSes directly when strict thresholds are exceeded' do
      fixture = active_expansion_fixture
      expansion = fixture.fetch(:expansion)
      set_referenced!(fixture.fetch(:dataset), expansion.original_refquota + 100)
      stub_const("#{described_class}::STRICT_MAX_EXPANSIONS", 0)
      stub_const("#{described_class}::STRICT_OVERQUOTA_MB", 1)
      unlock_transaction_signer!
      allow(MailTemplate).to receive(:send_mail!).and_return(build_mail_log_double)

      expect { task.stop_vps }.to change {
        TransactionChain.where(type: 'TransactionChains::Lifetimes::Wrapper').count
      }.by(1)

      expect(TransactionChains::Vps::StopOverQuota).not_to have_received(:fire)
      expect(
        TransactionChain.where(type: 'TransactionChains::Lifetimes::Wrapper').last
          .transaction_chain_concerns
          .pluck(:class_name, :row_id)
      ).to include(['Vps', fixture.fetch(:vps).id])
    end

    it 'schedules StopOverQuota when normal thresholds are exceeded' do
      fixture = active_expansion_fixture
      expansion = fixture.fetch(:expansion)
      set_referenced!(fixture.fetch(:dataset), expansion.original_refquota + 100)
      set_vps_running!(fixture.fetch(:vps))

      task.stop_vps

      expect(TransactionChains::Vps::StopOverQuota).to have_received(:fire).with(expansion)
      expect(expansion.reload.last_vps_stop).to be_present
    end

    it 'does not schedule repeated stops during cooldown' do
      fixture = active_expansion_fixture
      expansion = fixture.fetch(:expansion)
      set_referenced!(fixture.fetch(:dataset), expansion.original_refquota + 100)
      set_vps_running!(fixture.fetch(:vps), uptime: 7200)
      expansion.update!(last_vps_stop: 10.minutes.ago)
      stub_const("#{described_class}::COOLDOWN", 3600)

      task.stop_vps

      expect(TransactionChains::Vps::StopOverQuota).not_to have_received(:fire)
    end

    it 'warns and skips locked VPSes' do
      fixture = active_expansion_fixture
      expansion = fixture.fetch(:expansion)
      set_referenced!(fixture.fetch(:dataset), expansion.original_refquota + 100)
      set_vps_running!(fixture.fetch(:vps))
      allow(TransactionChains::Vps::StopOverQuota).to receive(:fire).and_raise(
        ResourceLocked.new(fixture.fetch(:vps), 'locked')
      )

      expect { task.stop_vps }.to output(/VPS #{fixture.fetch(:vps).id} is locked/).to_stderr
    end
  end

  describe '#resolve_datasets' do
    before do
      allow(TransactionChains::Vps::ShrinkDataset).to receive(:fire)
    end

    it 'warns and skips expansions without a primary dataset in pool' do
      fixture = active_expansion_fixture
      fixture.fetch(:pool).update!(role: :backup)

      expect { task.resolve_datasets }.to output(/No primary dataset in pool/).to_stderr

      expect(TransactionChains::Vps::ShrinkDataset).not_to have_received(:fire)
      expect(fixture.fetch(:expansion).reload.last_shrink).to be_nil
    end

    it 'does not schedule shrink during cooldown' do
      fixture = active_expansion_fixture
      expansion = fixture.fetch(:expansion)
      set_referenced!(fixture.fetch(:dataset_in_pool), 0)
      expansion.update!(last_shrink: 5.minutes.ago, created_at: 1.day.ago)
      stub_const("#{described_class}::COOLDOWN", 3600)

      task.resolve_datasets

      expect(TransactionChains::Vps::ShrinkDataset).not_to have_received(:fire)
    end

    it 'schedules shrink only when free-space criteria are met' do
      free_fixture = active_expansion_fixture
      full_fixture = active_expansion_fixture
      free_expansion = free_fixture.fetch(:expansion)
      full_expansion = full_fixture.fetch(:expansion)
      set_referenced!(free_fixture.fetch(:dataset_in_pool), 0)
      set_referenced!(full_fixture.fetch(:dataset_in_pool), full_expansion.original_refquota)
      free_expansion.update!(created_at: 1.day.ago)
      full_expansion.update!(created_at: 1.day.ago)

      task.resolve_datasets

      expect(TransactionChains::Vps::ShrinkDataset).to have_received(:fire).once.with(
        free_fixture.fetch(:dataset_in_pool),
        free_expansion
      )
      expect(free_expansion.reload.last_shrink).to be_present
      expect(full_expansion.reload.last_shrink).to be_nil
    end
  end
end
