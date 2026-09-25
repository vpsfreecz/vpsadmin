# frozen_string_literal: true

require 'spec_helper'
require 'timeout'

RSpec.describe StorageMutationAdmission do
  def session_for(admin)
    create_open_session!(user: admin, auth_type: 'basic')
  end

  def freeze!(admin:, session:, epoch:)
    described_class.set_read_only_for_user!(
      read_only: true, expected_epoch: epoch, reason: 'planned maintenance',
      user: admin, user_session: session
    )
  end

  it 'copies the locked direct administrator and session into the transition' do
    admin = SpecSeed.admin
    session = session_for(admin)
    epoch = StorageFreezeControl.singleton!.epoch

    freeze!(admin:, session:, epoch:)

    event = StorageFreezeTransition.order(:id).last
    expect(event).to have_attributes(
      actor_user_id: admin.id, actor_user_login: admin.login,
      actor_user_session_id: session.id
    )
    expect(event).not_to respond_to(:operator_uid)
    expect(StorageFreezeControl.singleton!.requested_by_user_id).to eq(admin.id)
  end

  it 'refuses a closed, delegated, or suspended session before changing mode' do
    admin = SpecSeed.admin
    session = session_for(admin)
    epoch = StorageFreezeControl.singleton!.epoch
    previous_events = StorageFreezeTransition.count

    session.update_columns(closed_at: Time.current)
    expect { freeze!(admin:, session:, epoch:) }
      .to raise_error(described_class::AuthorizationRefused)

    session.update_columns(closed_at: nil, admin_id: admin.id)
    expect { freeze!(admin:, session:, epoch:) }
      .to raise_error(described_class::AuthorizationRefused)

    session.update_columns(admin_id: nil)
    admin.update_columns(object_state: User.object_states.fetch(:suspended))
    expect { freeze!(admin:, session:, epoch:) }
      .to raise_error(described_class::AuthorizationRefused)

    expect(StorageFreezeControl.singleton!).to have_attributes(mode: 'read_write', epoch:)
    expect(StorageFreezeTransition.count).to eq(previous_events)
  end

  it 'serializes concurrent API freeze requests at one expected epoch', :no_transaction do
    admin = SpecSeed.admin
    session = session_for(admin)
    control = StorageFreezeControl.singleton!
    control.update_columns(mode: 0)
    epoch = control.epoch
    previous_events = StorageFreezeTransition.count
    ready = Queue.new
    go = Queue.new

    threads = 2.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          go.pop
          begin
            freeze!(admin:, session:, epoch:)
            :changed
          rescue StorageMutationAdmission::StaleEpoch
            :stale
          end
        end
      end
    end
    Timeout.timeout(5) { 2.times { ready.pop } }
    2.times { go << true }
    expect(Timeout.timeout(5) { threads.map(&:value) }).to contain_exactly(:changed, :stale)
    expect(StorageFreezeTransition.count).to eq(previous_events + 1)
    expect(StorageFreezeControl.singleton!).to have_attributes(mode: 'read_only', epoch: epoch + 1)
  ensure
    2.times { go << true } if go
    threads&.each { |thread| thread.join(5) }
    StorageFreezeTransition.where(new_epoch: epoch + 1).delete_all if epoch
    StorageFreezeControl.singleton!.update_columns(mode: 0, epoch:) if epoch
  end
end
