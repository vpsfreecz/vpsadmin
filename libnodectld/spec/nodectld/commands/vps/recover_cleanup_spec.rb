# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/commands/base'
require 'nodectld/commands/vps/recover_cleanup'

RSpec.describe NodeCtld::Commands::Vps::RecoverCleanup do
  let(:driver) { build_storage_driver }
  let(:cleaned_result) do
    {
      outcome: 'cleaned',
      incarnation_id: 'incarnation-1',
      run_id: 'tank:101:run-1',
      lifecycle_revision: 7,
      requested_cleanup: ['cgroups'],
      completed_cleanup: ['cgroups'],
      active_slot_released: false,
      residual_run_ids: [],
      evidence: {
        observed_at: 1_721_234_567.0,
        requested: ['cgroups'],
        lxc_state: 'stopped',
        lxc_state_source: 'osctld-cache'
      },
      hazards: []
    }
  end
  let(:cmd) do
    described_class.new(
      driver,
      'vps_id' => 101,
      'cgroups' => true,
      'network_interfaces' => false
    )
  end

  it 'passes only enabled cleanup flags to osctl' do
    result = Struct.new(:output).new(JSON.generate(cleaned_result))
    allow(cmd).to receive(:osctl).and_return(result)

    expect(cmd.exec).to eq(ret: :ok)
    expect(cmd).to have_received(:osctl).with(
      %i[ct recover cleanup],
      101,
      cgroups: true
    )
    expect(cmd.output[:recovery_cleanup]).to include(
      outcome: 'cleaned',
      completed_cleanup: ['cgroups'],
      evidence: include(requested: ['cgroups'])
    )
  end

  it 'accepts evidence for every requested cleanup operation' do
    both_cmd = described_class.new(
      driver,
      'vps_id' => 101,
      'cgroups' => true,
      'network_interfaces' => true
    )
    requested = %w[cgroups netifs]
    result = Struct.new(:output).new(
      JSON.generate(
        cleaned_result.merge(
          requested_cleanup: requested,
          completed_cleanup: requested,
          evidence: cleaned_result[:evidence].merge(requested:)
        )
      )
    )
    allow(both_cmd).to receive(:osctl).and_return(result)

    expect(both_cmd.exec).to eq(ret: :ok)
    expect(both_cmd).to have_received(:osctl).with(
      %i[ct recover cleanup],
      101,
      cgroups: true,
      network_interfaces: true
    )
  end

  it 'compares cleanup operations as sets' do
    both_cmd = described_class.new(
      driver,
      'vps_id' => 101,
      'cgroups' => true,
      'network_interfaces' => true
    )
    result = Struct.new(:output).new(
      JSON.generate(
        cleaned_result.merge(
          requested_cleanup: %w[netifs cgroups],
          completed_cleanup: %w[cgroups netifs],
          evidence: cleaned_result[:evidence].merge(
            requested: %w[netifs cgroups]
          )
        )
      )
    )
    allow(both_cmd).to receive(:osctl).and_return(result)

    expect(both_cmd.exec).to eq(ret: :ok)
  end

  it 'rejects duplicate cleanup operations in cleaned evidence' do
    result = Struct.new(:output).new(
      JSON.generate(
        cleaned_result.merge(
          completed_cleanup: %w[cgroups cgroups]
        )
      )
    )
    allow(cmd).to receive(:osctl).and_return(result)

    expect(cmd.exec).to eq(ret: :warning)
    expect(cmd.output[:recovery_cleanup]).to include(
      outcome: 'legacy_unknown'
    )
  end

  it 'expects all cleanup operations when no flags are enabled' do
    all_cmd = described_class.new(
      driver,
      'vps_id' => 101,
      'cgroups' => false,
      'network_interfaces' => false
    )
    requested = %w[cgroups netifs]
    result = Struct.new(:output).new(
      JSON.generate(
        cleaned_result.merge(
          requested_cleanup: requested,
          completed_cleanup: requested,
          evidence: cleaned_result[:evidence].merge(requested:)
        )
      )
    )
    allow(all_cmd).to receive(:osctl).and_return(result)

    expect(all_cmd.exec).to eq(ret: :ok)
    expect(all_cmd).to have_received(:osctl).with(
      %i[ct recover cleanup],
      101,
      {}
    )
  end

  it 'does not accept a bare cleaned outcome as proof of cleanup' do
    result = Struct.new(:output).new(JSON.generate(outcome: 'cleaned'))
    allow(cmd).to receive(:osctl).and_return(result)

    expect(cmd.exec).to eq(ret: :warning)
    expect(cmd.output[:recovery_cleanup]).to include(
      outcome: 'legacy_unknown',
      reported_cleanup: include(outcome: 'cleaned')
    )
    expect(cmd.output[:warnings]).to include(
      /incomplete structured cleanup evidence/
    )
  end

  %i[
    incarnation_id
    run_id
    lifecycle_revision
    requested_cleanup
    completed_cleanup
    active_slot_released
    residual_run_ids
    evidence
    hazards
  ].each do |key|
    it "does not accept cleaned evidence without #{key}" do
      result = Struct.new(:output).new(JSON.generate(cleaned_result.except(key)))
      allow(cmd).to receive(:osctl).and_return(result)

      expect(cmd.exec).to eq(ret: :warning)
      expect(cmd.output[:recovery_cleanup]).to include(
        outcome: 'legacy_unknown',
        reported_cleanup: include(outcome: 'cleaned')
      )
      expect(cmd.output[:warnings]).to include(
        /incomplete structured cleanup evidence/
      )
    end
  end

  %i[observed_at requested lxc_state lxc_state_source].each do |key|
    it "does not accept cleaned evidence without evidence #{key}" do
      result = Struct.new(:output).new(
        JSON.generate(
          cleaned_result.merge(evidence: cleaned_result[:evidence].except(key))
        )
      )
      allow(cmd).to receive(:osctl).and_return(result)

      expect(cmd.exec).to eq(ret: :warning)
      expect(cmd.output[:recovery_cleanup]).to include(
        outcome: 'legacy_unknown',
        reported_cleanup: include(outcome: 'cleaned')
      )
      expect(cmd.output[:warnings]).to include(
        /incomplete structured cleanup evidence/
      )
    end
  end

  it 'warns when cleanup completed for only part of the request' do
    both_cmd = described_class.new(
      driver,
      'vps_id' => 101,
      'cgroups' => true,
      'network_interfaces' => true
    )
    result = Struct.new(:output).new(
      JSON.generate(
        cleaned_result.merge(
          requested_cleanup: %w[cgroups netifs],
          completed_cleanup: ['cgroups'],
          evidence: cleaned_result[:evidence].merge(
            requested: %w[cgroups netifs]
          )
        )
      )
    )
    allow(both_cmd).to receive(:osctl).and_return(result)

    expect(both_cmd.exec).to eq(ret: :warning)
    expect(both_cmd.output[:recovery_cleanup]).to include(
      outcome: 'legacy_unknown',
      reported_cleanup: include(outcome: 'cleaned')
    )
    expect(both_cmd.output[:warnings]).to include(
      /incomplete structured cleanup evidence/
    )
  end

  {
    'cleanup evidence describes a different request' => {
      evidence: {
        observed_at: 1_721_234_567.0,
        requested: ['netifs'],
        lxc_state: 'stopped',
        lxc_state_source: 'osctld-cache'
      }
    },
    'cleaned response contains hazards' => {
      hazards: ['cleanup could not be proven']
    }
  }.each do |description, changes|
    it "warns when #{description}" do
      result = Struct.new(:output).new(
        JSON.generate(cleaned_result.merge(changes))
      )
      allow(cmd).to receive(:osctl).and_return(result)

      expect(cmd.exec).to eq(ret: :warning)
      expect(cmd.output[:recovery_cleanup]).to include(
        outcome: 'legacy_unknown',
        reported_cleanup: include(outcome: 'cleaned')
      )
      expect(cmd.output[:warnings]).to include(
        /incomplete structured cleanup evidence/
      )
    end
  end

  it 'records qualified partial cleanup as a warning and continues' do
    result = Struct.new(:output).new(
      JSON.generate(
        outcome: 'partial',
        hazards: ['generation cgroups were not requested for cleanup'],
        completed_cleanup: ['netifs']
      )
    )
    allow(cmd).to receive(:osctl).and_return(result)

    expect(cmd.exec).to eq(ret: :warning)
    expect(cmd.output).to include(
      recovery_cleanup: include(
        outcome: 'partial',
        completed_cleanup: ['netifs']
      ),
      warnings: ['generation cgroups were not requested for cleanup']
    )
  end

  it 'parses structured cleanup after human-readable progress' do
    result = Struct.new(:output).new(
      [
        'network cleanup used legacy route discovery',
        JSON.generate(
          outcome: 'partial',
          hazards: ['network cleanup used legacy route discovery'],
          completed_cleanup: ['netifs']
        )
      ].join("\n")
    )
    allow(cmd).to receive(:osctl).and_return(result)

    expect(cmd.exec).to eq(ret: :warning)
    expect(cmd.output).to include(
      recovery_cleanup: include(
        outcome: 'partial',
        completed_cleanup: ['netifs']
      ),
      warnings: ['network cleanup used legacy route discovery']
    )
  end

  it 'records quarantined cleanup evidence as a warning and continues' do
    result = Struct.new(:output).new(
      JSON.generate(
        outcome: 'quarantined',
        hazards: ['already-entered kernel or ZFS operations may complete later'],
        residual_run_ids: ['tank:101:abc123']
      )
    )
    allow(cmd).to receive(:osctl).and_return(result)

    expect(cmd.exec).to eq(ret: :warning)
    expect(cmd.output[:recovery_cleanup]).to include(
      outcome: 'quarantined',
      residual_run_ids: ['tank:101:abc123']
    )
  end

  it 'records old node responses as legacy unknown and continues' do
    result = Struct.new(:output).new('')
    allow(cmd).to receive(:osctl).and_return(result)

    expect(cmd.exec).to eq(ret: :warning)
    expect(cmd.output[:recovery_cleanup]).to include(outcome: 'legacy_unknown')
    expect(cmd.output[:warnings]).to include(/no structured cleanup evidence/)
  end

  {
    'malformed output' => 'cleanup finished without structured evidence',
    'JSON null' => 'null',
    'a JSON scalar' => JSON.generate('cleaned'),
    'a JSON array' => JSON.generate([{ outcome: 'cleaned' }])
  }.each do |description, osctl_output|
    it "records #{description} as legacy unknown and continues" do
      result = Struct.new(:output).new(osctl_output)
      allow(cmd).to receive(:osctl).and_return(result)

      expect(cmd.exec).to eq(ret: :warning)
      expect(cmd.output[:recovery_cleanup]).to include(outcome: 'legacy_unknown')
      expect(cmd.output[:warnings]).to include(/no structured cleanup evidence/)
    end
  end

  %w[blocked ambiguous unexpected].each do |outcome|
    it "rejects structured #{outcome} outcomes" do
      result = Struct.new(:output).new(
        JSON.generate(outcome:, hazards: ["cleanup outcome is #{outcome}"])
      )
      allow(cmd).to receive(:osctl).and_return(result)

      expect { cmd.exec }
        .to raise_error("unsupported recovery cleanup outcome #{outcome.inspect}")
    end
  end

  it 'has a no-op rollback' do
    expect(cmd.rollback).to eq(ret: :ok)
  end
end
