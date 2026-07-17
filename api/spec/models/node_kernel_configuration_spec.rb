# frozen_string_literal: true

RSpec.describe NodeKernelConfiguration do
  it 'keeps canonical configurations and parsed options immutable' do
    content = "CONFIG_IPV6=y\n"
    config = VpsAdmin::API::KernelEvidence::ConfigurationWriter.call(
      digest: Digest::SHA256.hexdigest(content),
      content:
    )

    expect { config.update!(content: "CONFIG_IPV6=n\n") }
      .to raise_error(ActiveRecord::ReadOnlyRecord)
    expect { config.destroy! }.to raise_error(ActiveRecord::ReadOnlyRecord)

    config.reload
    option = NodeKernelConfigurationOption.find_by!(node_kernel_configuration: config)
    expect { option.update!(value: 'n') }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect { option.destroy! }.to raise_error(ActiveRecord::ReadOnlyRecord)

    expect(config.reload.kernel_configuration_options.pluck(:name, :value).to_h)
      .to eq('CONFIG_IPV6' => 'y')
  end

  it 'rejects content that does not match the digest' do
    config = described_class.new(digest: 'a' * 64, content: "CONFIG_IPV6=y\n")

    expect(config).not_to be_valid
    expect(config.errors[:digest]).to include('does not match configuration content')
  end
end
