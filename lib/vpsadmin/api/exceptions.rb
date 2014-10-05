module VpsAdmin::API::Exceptions
  class IpAddressInUse < ::StandardError

  end

  class IpAddressNotAssigned < ::StandardError

  end

  class IpAddressInvalidLocation < ::StandardError

  end
end
