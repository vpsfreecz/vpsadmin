module NodeCtld::Utils
  module Hypervisor
    def sample_conf_path(name)
      "#{$CFG.get(:vz, :vz_conf)}/conf/ve-#{name}.conf-sample"
    end
  end
end
