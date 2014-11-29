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

  class DatasetDoesNotExist < ::StandardError
    attr_reader :path

    def initialize(path)
      @path = path
      super("dataset '#{path}' does not exist")
    end
  end
end
