module VpsAdmin::API::KernelEvidence
  class ConfigurationWriter
    def self.call(digest:, content:) = new(digest:, content:).call

    def initialize(digest:, content:)
      @digest = digest
      @content = content
    end

    def call
      configuration = nil
      ::NodeKernelConfiguration.transaction(requires_new: true) do
        configuration = ::NodeKernelConfiguration.find_or_initialize_by(digest: @digest)
        verify_content!(configuration) if configuration.persisted?
        next if configuration.persisted?

        configuration.content = @content
        configuration.save!
        rows = ConfigurationParser.call(@content).map do |name, value|
          {
            node_kernel_configuration_id: configuration.id,
            name:,
            value:
          }
        end
        ::NodeKernelConfigurationOption.insert_all!(rows) unless rows.empty?
      end
      configuration
    rescue ActiveRecord::RecordNotUnique
      configuration = ::NodeKernelConfiguration.find_by!(digest: @digest)
      verify_content!(configuration)
      configuration
    end

    protected

    def verify_content!(configuration)
      return if configuration.content == @content

      raise ArgumentError, 'kernel configuration digest collision'
    end
  end
end
