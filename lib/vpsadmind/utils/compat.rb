module VpsAdmind
  module Utils::Compat
    def class_from_name(name)
      name.split('::').inject(Object) do |mod, part|
        mod.const_get(part)
      end
    end
  end
end