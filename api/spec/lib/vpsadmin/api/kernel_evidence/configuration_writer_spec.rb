# frozen_string_literal: true

RSpec.describe VpsAdmin::API::KernelEvidence::ConfigurationWriter do
  it 'stores enabled, module, assigned and disabled Linux configuration options' do
    content = <<~CONFIG
      CONFIG_IPV6=y
      CONFIG_KVM=m
      CONFIG_CMDLINE="quiet"
      # CONFIG_NF_TABLES is not set
      unrelated text
    CONFIG
    config = described_class.call(
      digest: Digest::SHA256.hexdigest(content),
      content:
    )

    expect(config.kernel_configuration_options.order(:name).pluck(:name, :value).to_h).to eq(
      'CONFIG_CMDLINE' => '"quiet"',
      'CONFIG_IPV6' => 'y',
      'CONFIG_KVM' => 'm',
      'CONFIG_NF_TABLES' => 'n'
    )
  end

  it 'uses the last value when an option is assigned more than once' do
    content = "CONFIG_IPV6=n\nCONFIG_IPV6=y\n"
    config = described_class.call(
      digest: Digest::SHA256.hexdigest(content),
      content:
    )

    expect(config.kernel_configuration_options.pluck(:name, :value).to_h)
      .to eq('CONFIG_IPV6' => 'y')
  end

  it 'deduplicates identical content and rejects digest collisions' do
    content = "CONFIG_IPV6=y\n"
    digest = Digest::SHA256.hexdigest(content)

    first = described_class.call(digest:, content:)
    second = described_class.call(digest:, content:)

    expect(second).to eq(first)
    expect(NodeKernelConfiguration.where(digest:).count).to eq(1)
    expect do
      described_class.call(digest:, content: "CONFIG_IPV6=n\n")
    end.to raise_error(ArgumentError, 'kernel configuration digest collision')
  end
end
