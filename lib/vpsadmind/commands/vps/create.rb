module VpsAdmind
  class Commands::Vps::Create < Commands::Base
    handle 3001

    def exec
      Vps.new(@vps_id).create(@template, @hostname, @nameserver)
      # FIXME: what about onboot param?
    end
  end
end
