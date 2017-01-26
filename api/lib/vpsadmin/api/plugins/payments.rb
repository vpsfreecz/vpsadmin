module VpsAdmin::API::Plugins::Payments
  def self.register_backend(name, klass)
    @backends ||= {}
    @backends[name] = klass
  end

  def self.get_backend(name)
    @backends && @backends[name]
  end
end
