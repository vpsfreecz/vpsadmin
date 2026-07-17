# frozen_string_literal: true

require 'spec_helper'

RSpec.describe NodeSystemHistoryState do
  let(:node) { SpecSeed.node }

  before do
    node.node_system_history_state&.destroy!
  end

  it 'belongs to one Node and is exposed through the private Node association' do
    state = described_class.create!(node:, completed_at: Time.current)

    expect(node.reload.node_system_history_state).to eq(state)
    expect(state.node).to eq(node)
  end

  it 'requires one unique completed checkpoint per Node' do
    described_class.create!(node:, completed_at: Time.current)
    duplicate = described_class.new(node:, completed_at: Time.current)
    missing_completion = described_class.new(node:)

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:node_id]).to be_present
    expect(missing_completion).not_to be_valid
    expect(missing_completion.errors[:completed_at]).to be_present
  end

  it 'is deleted with its Node association' do
    state = described_class.create!(node:, completed_at: Time.current)

    expect(node.association(:node_system_history_state).options[:dependent]).to eq(:destroy)
    expect(state).to be_persisted
  end
end
