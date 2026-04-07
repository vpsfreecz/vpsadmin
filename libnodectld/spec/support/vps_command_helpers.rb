# frozen_string_literal: true

module NodeCtldSpec
  module VpsCommandHelpers
    def build_vps_driver(id: 321)
      instance_double(
        NodeCtld::Command,
        id: id,
        progress: nil,
        'progress=': nil,
        log_type: :spec
      )
    end

    def stub_vps_instance(vps_id, methods = {})
      vps = instance_spy(NodeCtld::Vps, methods)

      allow(NodeCtld::Vps).to receive(:new).with(vps_id).and_return(vps)

      vps
    end
  end
end
