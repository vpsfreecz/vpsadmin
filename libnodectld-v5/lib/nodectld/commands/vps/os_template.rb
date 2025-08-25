module NodeCtld
  class Commands::Vps::OsTemplate < Commands::Base
    handle 2013
    needs :system, :osctl, :vps

    def exec
      osctl(
        %i[ct set distribution],
        [
          @vps_id,
          @new['distribution'],
          @new['version'],
          @new['arch'],
          @new['vendor'],
          @new['variant']
        ]
      )
    end

    def rollback
      osctl(
        %i[ct set distribution],
        [
          @vps_id,
          @original['distribution'],
          @original['version'],
          @original['arch'],
          @original['vendor'],
          @original['variant']
        ]
      )
    end
  end
end
