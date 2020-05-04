module NodeCtld
  class Commands::Vps::OsTemplate < Commands::Base
    handle 2013
    needs :system, :osctl, :vps

    def exec
      honor_state do
        osctl(%i(ct stop), @vps_id)
        osctl(
          %i(ct set image-config),
          @vps_id,
          {distribution: @new['distribution'], version: @new['version']}
        )
      end
    end

    def rollback
      honor_state do
        osctl(%i(ct stop), @vps_id)
        osctl(
          %i(ct set image-config),
          @vps_id,
          {distribution: @original['distribution'], version: @original['version']}
        )
      end
    end
  end
end
