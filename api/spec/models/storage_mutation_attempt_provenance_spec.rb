# frozen_string_literal: true

require 'spec_helper'

RSpec.describe StorageMutationAttempt do
  let(:intent) do
    StorageMutationIntent.create!(
      token: SecureRandom.uuid, node: SpecSeed.node, kind: 'snapshot_create',
      manifest_digest: 'a' * 64, protocol_version: 1
    )
  end

  def attempt(attrs = {})
    described_class.new({
      storage_mutation_intent: intent, command_key: '5204',
      direction: :execute, attempt_number: 1, state: :started
    }.merge(attrs))
  end

  it 'accepts observer and strict provenance at creation' do
    expect(attempt).to be_valid
    strict = attempt(
      strict_dispatch_registry_version: 3, strict_signed_input_digest: 'b' * 64
    )
    expect(strict).to be_valid
    strict.save!
    expect(strict.reload.strict_signed_input_digest).to eq('b' * 64)
  end

  it 'rejects one-sided or malformed strict provenance' do
    expect(attempt(strict_dispatch_registry_version: 3)).not_to be_valid
    expect(attempt(strict_signed_input_digest: 'b' * 64)).not_to be_valid
    expect(attempt(strict_dispatch_registry_version: 3,
                   strict_signed_input_digest: 'B' * 64)).not_to be_valid
  end

  it 'never promotes or changes provenance after the started insert' do
    observer = attempt
    observer.save!
    expect do
      observer.update!(strict_dispatch_registry_version: 3,
                       strict_signed_input_digest: 'b' * 64)
    end.to raise_error(ActiveRecord::RecordInvalid)
    observer.reload
    expect do
      observer.update!(strict_dispatch_registry_version: 3)
    end.to raise_error(ActiveRecord::RecordInvalid)

    strict = attempt(
      attempt_number: 2, strict_dispatch_registry_version: 3,
      strict_signed_input_digest: 'c' * 64
    )
    strict.save!
    expect do
      strict.update!(strict_signed_input_digest: 'd' * 64)
    end.to raise_error(ActiveRecord::RecordInvalid)
    strict.reload
    expect do
      strict.update!(strict_dispatch_registry_version: nil,
                     strict_signed_input_digest: nil)
    end.to raise_error(ActiveRecord::RecordInvalid)
    strict.reload
    strict.update!(state: :succeeded, finished_at: Time.now.utc)
    expect(strict.reload).to be_succeeded
  end
end
