# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::Tasks::Snapshot do
  let(:task) { described_class.new }

  it 'fires the snapshot clone purge chain' do
    allow(TransactionChains::SnapshotInPool::PurgeClones).to receive(:fire)

    task.purge_clones

    expect(TransactionChains::SnapshotInPool::PurgeClones).to have_received(:fire)
  end
end
