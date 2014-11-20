module VpsAdmin::API::Exceptions
  class IpAddressInUse < ::StandardError

  end

  class IpAddressNotAssigned < ::StandardError

  end

  class IpAddressInvalidLocation < ::StandardError

  end

  class DatasetAlreadyExists < ::StandardError
    attr_reader :dataset, :path

    def initialize(ds, path)
      @dataset = ds
      @path = path
      super("dataset '#{path}' already exists")
    end
  end
end
