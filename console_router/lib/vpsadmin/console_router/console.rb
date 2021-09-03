module VpsAdmin::ConsoleRouter
  class Console < EventMachine::Connection
    attr_accessor :buf, :last_access, :w, :h

    def initialize(vps_id, params, router)
      @vps_id = vps_id
      @session = params[:session]
      @w = params[:width].to_i
      @h = params[:height].to_i
      @router = router
      @buf = ""
      update_access
    end

    def post_init
      send_data({
        session: @session,
        width: @w,
        height: @h,
      }.to_json + "\n")
    end

    def receive_data(data)
      @buf += data
    end

    def unbind
      @router.disconnected(@vps_id)
    end

    def update_access
      @last_access = Time.new
    end
  end
end
