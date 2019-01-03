module NodeCtld
  class Commands::Vps::OsTemplate < Commands::Base
    handle 2013
    needs :system, :osctl

    def exec
      osctl(
        %i(ct set distribution),
        [@vps_id, @new['distribution'], @new['version']]
      )
    end

    def rollback
      osctl(
        %i(ct set distribution),
        [@vps_id, @original['distribution'], @original['version']]
      )
    end
  end
end
