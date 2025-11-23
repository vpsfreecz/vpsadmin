module NodeCtld
  class VpsConfig::UserData
    # @param data [Hash]
    def self.load(data)
      new(format: data.fetch('format'), content: data.fetch('content'))
    end

    # @return [String]
    attr_reader :format

    # @return [String]
    attr_reader :content

    def initialize(format:, content:)
      @format = format
      @content = content
    end

    # @return [Hash]
    def save
      {
        'format' => format,
        'content' => content
      }
    end
  end
end
