module VpsAdmind
  module Firewall
    class << self
      %i(instance get synchronize accounting ip_map networks).each do |m|
        define_method(m) { |*args, &block| VpsAdmind::Firewall::Main.send(m, *args, &block) }
      end
    end
  end
end
