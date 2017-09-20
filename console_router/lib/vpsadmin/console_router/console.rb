module VpsAdmin::ConsoleRouter
  class Console < EventMachine::Connection
    attr_accessor :buf, :last_access, :w, :h

    def initialize(veid, params, router)
      @veid = veid
      @session = params[:session]
      @w = params[:width]
      @h = params[:height]
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
      @router.disconnected(@veid)
    end

    def update_access
      @last_access = Time.new
    end
  end
end
