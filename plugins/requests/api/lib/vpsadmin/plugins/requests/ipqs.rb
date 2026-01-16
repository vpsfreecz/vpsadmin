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
      "https://www.ipqualityscore.com/api/json/ip/#{api_key}/#{addr}?" \
      "strictness=#{strictness}"
    )

    resp = Net::HTTP.get(uri)

    begin
      Response.new(resp)
    rescue JSON::ParserError
      raise "Unable to parse response as JSON: addr=#{addr.inspect} uri=#{uri.inspect} response=#{resp.inspect}"
    end
  end

  def check_mail(mail, strictness: 0)
    uri = URI(
      "https://www.ipqualityscore.com/api/json/email/#{api_key}/#{mail}?" \
      "strictness=#{strictness}"
    )

    resp = Net::HTTP.get(uri)

    begin
      Response.new(resp)
    rescue JSON::ParserError
      raise "Unable to parse response as JSON: mail=#{mail.inspect} uri=#{uri.inspect} response=#{resp.inspect}"
    end
  end

  protected

  attr_reader :api_key
end
