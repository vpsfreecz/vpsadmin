# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::Tasks::Lifetime do
  around do |example|
    with_current_context(user: SpecSeed.admin) { example.run }
  end

  let(:task) { described_class.new }

  def create_lifetime_user!(login_prefix: 'life', state: :active, expiration_date: 1.day.ago,
                            remind_after_date: nil, created_at: Time.now.utc)
    user = SpecSeed.create_or_update_user!(
      login: "#{login_prefix}-#{SecureRandom.hex(4)}",
      level: 1,
      email: "#{login_prefix}@test.invalid"
    )
    user.update_columns(
      object_state: User.object_states.fetch(state.to_s),
      expiration_date:,
      remind_after_date:,
      created_at:
    )
    user.reload
  end

  def create_lifetime_vps!(expiration_date: 1.day.ago, state: :active)
    vps = build_standalone_vps_fixture(user: SpecSeed.user).fetch(:vps)
    vps.update_columns(
      object_state: Vps.object_states.fetch(state.to_s),
      expiration_date:
    )
    vps.reload
  end

  describe '#progress' do
    # rubocop:disable RSpec/AnyInstance
    before do
      allow_any_instance_of(User).to receive(:progress_object_state) do |record, _direction, **_opts|
        record.update!(object_state: :suspended)
      end
      allow_any_instance_of(Vps).to receive(:progress_object_state) do |record, _direction, **_opts|
        record.update!(object_state: :suspended)
      end
    end
    # rubocop:enable RSpec/AnyInstance

    it 'does not progress state in dry-run mode' do
      user = create_lifetime_user!

      with_env('OBJECTS' => 'User') do
        task.progress
      end

      expect(user.reload.object_state).to eq('active')
    end

    it 'progresses eligible objects when EXECUTE is yes' do
      user = create_lifetime_user!

      with_env('OBJECTS' => 'User', 'EXECUTE' => 'yes') do
        task.progress
      end

      expect(user.reload.object_state).to eq('suspended')
    end

    it 'filters objects and states' do
      user = create_lifetime_user!
      vps = create_lifetime_vps!

      with_env('OBJECTS' => 'User', 'STATES' => 'active', 'EXECUTE' => 'yes') do
        task.progress
      end

      expect(user.reload.object_state).to eq('suspended')
      expect(vps.reload.object_state).to eq('active')
    end

    it 'uses language-specific reasons' do
      user = create_lifetime_user!
      captured_reason = nil
      # rubocop:disable RSpec/AnyInstance
      allow_any_instance_of(User).to receive(:progress_object_state) do |record, _direction, **opts|
        captured_reason = opts.fetch(:reason)
        record.update!(object_state: :suspended)
      end
      # rubocop:enable RSpec/AnyInstance

      with_env(
        'OBJECTS' => 'User',
        'EXECUTE' => 'yes',
        'REASON' => 'default reason',
        'REASON_EN' => 'english reason'
      ) do
        task.progress
      end

      expect(captured_reason).to eq('english reason')
    end

    it 'keeps old active users in the relaxation window' do
      user = create_lifetime_user!(
        expiration_date: 10.days.ago,
        created_at: 7.months.ago
      )

      expect do
        with_env('OBJECTS' => 'User', 'EXECUTE' => 'yes') do
          task.progress
        end
      end.to output(/we still love you/).to_stdout
      expect(user.reload.object_state).to eq('active')
    end

    it 'raises on invalid LIMIT' do
      create_lifetime_user!

      expect do
        with_env('OBJECTS' => 'User', 'LIMIT' => '0') do
          task.progress
        end
      end.to raise_error(RuntimeError, 'invalid limit')
    end
  end

  describe '#mail_expiration' do
    before do
      allow(TransactionChains::Lifetimes::ExpirationWarning).to receive(:fire)
    end

    it 'selects objects using FROM_DAYS' do
      selected = create_lifetime_vps!(expiration_date: 2.days.ago)
      skipped = create_lifetime_vps!(expiration_date: 12.hours.ago)
      fired_objects = nil
      allow(TransactionChains::Lifetimes::ExpirationWarning).to receive(:fire) do |_klass, objects|
        fired_objects = objects
      end

      with_env('OBJECTS' => 'Vps', 'FROM_DAYS' => '1', 'EXECUTE' => 'yes') do
        task.mail_expiration
      end

      expect(fired_objects.map(&:id)).to include(selected.id)
      expect(fired_objects.map(&:id)).not_to include(skipped.id)
    end

    it 'honors FORCE_DAY with FORCE_ONLY even when reminders are suppressed' do
      forced = create_lifetime_vps!(
        expiration_date: 1.day.ago
      )
      forced.update!(remind_after_date: 1.week.from_now)
      fired_objects = nil
      allow(TransactionChains::Lifetimes::ExpirationWarning).to receive(:fire) do |_klass, objects|
        fired_objects = objects
      end

      with_env(
        'OBJECTS' => 'Vps',
        'FROM_DAYS' => '0',
        'FORCE_DAY' => '1',
        'FORCE_ONLY' => 'yes',
        'EXECUTE' => 'yes'
      ) do
        task.mail_expiration
      end

      expect(fired_objects.map(&:id)).to include(forced.id)
    end

    it 'suppresses reminders until remind_after_date unless force triggers' do
      suppressed = create_lifetime_vps!(expiration_date: 2.days.ago)
      suppressed.update!(remind_after_date: 1.week.from_now)

      with_env('OBJECTS' => 'Vps', 'FROM_DAYS' => '0', 'EXECUTE' => 'yes') do
        task.mail_expiration
      end

      expect(TransactionChains::Lifetimes::ExpirationWarning).not_to have_received(:fire)
    end

    it 'does not fire a mail chain in dry-run mode' do
      create_lifetime_vps!(expiration_date: 2.days.ago)

      with_env('OBJECTS' => 'Vps', 'FROM_DAYS' => '0') do
        task.mail_expiration
      end

      expect(TransactionChains::Lifetimes::ExpirationWarning).not_to have_received(:fire)
    end

    it 'fires ExpirationWarning in execute mode for matching objects' do
      vps = create_lifetime_vps!(expiration_date: 2.days.ago)

      with_env('OBJECTS' => 'Vps', 'FROM_DAYS' => '0', 'EXECUTE' => 'yes') do
        task.mail_expiration
      end

      expect(TransactionChains::Lifetimes::ExpirationWarning).to have_received(:fire).with(
        Vps,
        include(vps)
      )
    end
  end
end
