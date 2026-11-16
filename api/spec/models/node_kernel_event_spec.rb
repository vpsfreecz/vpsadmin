# frozen_string_literal: true

require 'spec_helper'

RSpec.describe NodeKernelEvent do
  subject(:event) do
    described_class.new(
      node: SpecSeed.node,
      event_type: :livepatch_change,
      source: :node_report,
      confidence: :exact,
      reported_release: '6.12.113.1',
      observed_before: Time.utc(2026, 11, 16, 10, 25, 3),
      livepatch_id:
    )
  end

  context 'with no live patch ID' do
    let(:livepatch_id) { nil }

    it { is_expected.to be_valid }
  end

  context 'with a nonempty 63-byte live patch ID' do
    let(:livepatch_id) { 'a' * 63 }

    it { is_expected.to be_valid }
  end

  context 'with an empty live patch ID' do
    let(:livepatch_id) { '' }

    it { is_expected.not_to be_valid }
  end

  context 'with a live patch ID longer than 63 bytes' do
    let(:livepatch_id) { 'é' * 32 }

    it { is_expected.not_to be_valid }
  end
end
