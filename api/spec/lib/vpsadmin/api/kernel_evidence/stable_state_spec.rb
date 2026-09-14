# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::KernelEvidence::StableState do
  def report(boot_id: 'boot-a', booted_at: '2026-08-01T12:00:00Z', release: '6.12.93',
             livepatches: [], errors: [], modules: [])
    VpsAdmin::API::KernelEvidence::Report.from_hash(
      'schema_version' => 1,
      'kernel' => {
        'boot_id' => boot_id, 'booted_at' => booted_at, 'booted_release' => '6.12.93',
        'reported_release' => release, 'kernel_source_revision' => nil, 'config_digest' => nil,
        'booted_params' => [], 'command_line' => ''
      },
      'livepatches' => livepatches.map do |patch|
        { 'id' => 'patch', 'loaded' => true, 'enabled' => true, 'transition' => false,
          'kernel_version' => nil, 'patch_version' => nil, 'patches' => [] }.merge(patch)
      end,
      'ebpf_programs' => [], 'loaded_modules' => modules, 'software_versions' => [], 'sysctls' => {},
      'deployment' => { 'booted_system' => nil, 'current_system' => nil }, 'errors' => errors
    )
  end

  describe '.same_boot?' do
    it 'prefers boot IDs to boot timestamps when both are known' do
      expect(described_class.same_boot?(report.kernel, report(booted_at: nil).kernel)).to be(true)
      expect(described_class.same_boot?(report.kernel, report(boot_id: 'boot-b').kernel)).to be(false)
    end

    it 'falls back to matching known boot timestamps when an ID is missing' do
      expect(described_class.same_boot?(report.kernel, report(boot_id: nil).kernel)).to be(true)
      expect(described_class.same_boot?(report.kernel, report(boot_id: nil, booted_at: '2026-08-02T12:00:00Z').kernel))
        .to be(false)
    end

    it 'does not establish a boot from absent identities' do
      unknown = report(boot_id: nil, booted_at: nil)
      expect(described_class).not_to be_same_boot(unknown.kernel, unknown.kernel)
      expect(described_class).not_to be_stable(unknown)
    end
  end

  describe '.stable?' do
    it 'requires complete non-transitioning livepatch state' do
      expect(described_class.stable?(report)).to be(true)
      %w[loaded enabled transition].each do |attribute|
        expect(described_class.stable?(report(livepatches: [{ attribute => nil }]))).to be(false)
      end
      expect(described_class.stable?(report(livepatches: [{ 'transition' => true }]))).to be(false)
    end

    it 'rejects unreadable inventories and runtime flags but permits unavailable enrichment' do
      %w[livepatches livepatch.patch.enabled livepatch.patch.transition].each do |component|
        expect(described_class.stable?(report(errors: [{ 'component' => component, 'reason' => 'unavailable' }])))
          .to be(false)
      end
      expect(described_class.stable?(report(errors: [{
        'component' => 'livepatch.patch.metadata', 'reason' => 'unavailable'
      }]))).to be(true)
    end

    it 'rejects invalid reports and missing reported release' do
      expect(described_class.stable?(nil)).to be(false)
      expect(described_class)
        .not_to be_stable(VpsAdmin::API::KernelEvidence::Report.invalid(schema_version: 1, reason: 'bad'))
      expect(described_class.stable?(report(release: nil))).to be(false)
    end
  end

  describe '.confirms?' do
    it 'compares only stable boot, release, and effective patch IDs' do
      baseline = report(livepatches: [{ 'id' => 'a' }, { 'id' => 'b' }])
      enriched = report(livepatches: [
                          { 'id' => 'b', 'verified_at' => '2026-09-01T12:00:00Z', 'patch_version' => '2' },
                          { 'id' => 'a', 'applied_at' => '2026-08-01T12:01:00Z' },
                          { 'id' => 'available', 'loaded' => false, 'enabled' => false }
                        ], modules: ['unrelated'])
      expect(described_class.confirms?(baseline, enriched)).to be(true)
      expect(described_class.effective_ids(enriched.livepatches.reverse)).to eq(%w[a b])
    end

    it 'rejects release and effective-state mismatches, including a legacy hidden patch' do
      baseline = report(livepatches: [{}])
      expect(described_class.confirms?(baseline, report(release: '6.12.94', livepatches: [{}]))).to be(false)
      expect(described_class.confirms?(baseline, report(livepatches: [{ 'id' => 'other', 'loaded' => false }]))).to be(false)
      expect(described_class.confirms?(baseline, report(livepatches: [{ 'enabled' => false }]))).to be(false)
      expect(described_class.confirms?(baseline, report(boot_id: 'boot-b', livepatches: [{}]))).to be(false)
    end

    it 'cannot confirm an incomplete or transitioning baseline with a later stable report' do
      expect(described_class.confirms?(report(livepatches: [{ 'enabled' => nil }]), report)).to be(false)
      expect(described_class.confirms?(report(livepatches: [{ 'transition' => true }]), report)).to be(false)
    end
  end
end
