require 'json'
require 'net/http'

class VpsAdmin::API::Plugins::Requests::IPQS
  class Response
    def initialize(str)
      @data = JSON.parse(str, symbolize_names: true)
    end

    def [](key)
      @data[key]
    end

    def success?
      @data[:success] === true
    end
  end

  def initialize(api_key)
    @api_key = api_key
  end

  def check_ip(addr, strictness: 0)
    uri = URI(
      "https://www.ipqualityscore.com/api/json/ip/#{api_key}/#{addr}?"+
      "strictness=#{strictness}"
    )
    Response.new(Net::HTTP.get(uri))
  end

  def check_mail(mail, strictness: 0)
    uri = URI(
      "https://www.ipqualityscore.com/api/json/email/#{api_key}/#{mail}?"+
      "strictness=#{strictness}"
    )
    Response.new(Net::HTTP.get(uri))
  end

  protected
  attr_reader :api_key
end
