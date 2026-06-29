# frozen_string_literal: true

require 'erb'
require 'ripper'

module VpsAdmin
  module API
    module NotificationTemplates
      class InvalidTemplate < StandardError; end

      TEMPLATE_NAME_PATTERN = /\A[a-z0-9_]+\z/
      TEMPLATE_ATTRIBUTE_LIMIT = 100
      TRANSLATION_ATTRIBUTE_LIMIT = 255
      LANGUAGE_PATTERN = /\A[a-zA-Z]{2}\z/
      VARIANT_FILE_PATTERN = /\A(?<language>[a-zA-Z]{2})\.(?<format>subject|text|html)\.erb\z/
      PROTOCOLS = %w[email telegram sms].freeze
      DEFAULT_TELEGRAM_HTML =
        '<%= telegram_notification_html if respond_to?(:telegram_notification_html) %>'
      PROTOCOL_FORMATS = {
        'email' => %w[subject text html],
        'telegram' => %w[text html],
        'sms' => %w[text]
      }.freeze
      PROTOCOL_OPTIONS = {
        'email' => %i[from reply_to return_path subject],
        'telegram' => [],
        'sms' => []
      }.freeze
      TELEGRAM_ALLOWED_HTML_TAGS = %w[
        a b blockquote code del em i ins pre s span strike strong tg-spoiler u
      ].freeze

      def self.normalize_language(value, path:)
        language = value.to_s
        unless LANGUAGE_PATTERN.match?(language)
          raise InvalidTemplate, "#{path}: language must be a two-letter code, got #{language.inspect}"
        end

        language.downcase
      end

      class VariantOptions
        attr_reader :opts

        def initialize(protocol:)
          @protocol = protocol
          @opts = {}
        end

        def assign(name, value)
          unless PROTOCOL_OPTIONS.fetch(@protocol).include?(name)
            raise InvalidTemplate, "unsupported #{@protocol} option #{name.inspect}"
          end

          @opts[name] = value
        end
      end

      class Meta < VariantOptions
        TEMPLATE_OPTS = %i[label user_visibility].freeze

        attr_reader :id, :template_opts

        def initialize(id)
          super(protocol: 'email')
          @id = id
          @template_opts = {}
          @languages = {}
          @protocols = {}
        end

        def assign_template(name, value)
          raise InvalidTemplate, "unsupported template option #{name.inspect}" unless TEMPLATE_OPTS.include?(name)

          @template_opts[name] = value
        end

        def assign_variant(name, value)
          assign(name, value)
        end

        def add_language(code, options, path:)
          language = NotificationTemplates.normalize_language(code, path:)
          if @languages.has_key?(language)
            raise InvalidTemplate, "language #{language.inspect} is declared more than once"
          end

          @languages[language] = options
        end

        def add_protocol(name, defaults, languages, path:)
          protocol = name.to_s
          unless PROTOCOLS.include?(protocol)
            raise InvalidTemplate, "#{path}: unsupported template protocol #{protocol.inspect}"
          end
          if @protocols.has_key?(protocol)
            raise InvalidTemplate, "#{path}: protocol #{protocol.inspect} is declared more than once"
          end

          @protocols[protocol] = {
            defaults:,
            languages:
          }
        end

        def variant_options(protocol, language)
          protocol = protocol.to_s
          global_defaults = protocol == 'email' ? @opts : {}
          global_language = protocol == 'email' ? @languages.fetch(language, {}) : {}
          protocol_options = @protocols.fetch(protocol, {})

          global_defaults
            .merge(global_language)
            .merge(protocol_options.fetch(:defaults, {}))
            .merge(protocol_options.fetch(:languages, {}).fetch(language, {}))
        end

        def validate!(path)
          unless id.nil? || id.is_a?(String) || id.is_a?(Symbol)
            raise InvalidTemplate, "#{path}: template ID must be a string or symbol"
          end

          validate_string_option!(
            path,
            :template_id,
            id.nil? ? nil : id.to_s,
            allow_nil: true,
            allow_blank: false,
            limit: TEMPLATE_ATTRIBUTE_LIMIT
          )
          validate_string_option!(
            path,
            :label,
            @template_opts[:label],
            allow_nil: true,
            allow_blank: false,
            limit: TEMPLATE_ATTRIBUTE_LIMIT
          )

          visibility = @template_opts[:user_visibility]
          unless visibility.nil? || visibility == true || visibility == false
            raise InvalidTemplate, "#{path}: user_visibility must be true or false"
          end

          validate_variant_options!(path, @opts)
          @languages.each do |language, options|
            unless LANGUAGE_PATTERN.match?(language)
              raise InvalidTemplate, "#{path}: invalid language name #{language.inspect}"
            end

            validate_variant_options!(path, options, language:)
          end
          @protocols.each do |protocol, options|
            validate_variant_options!(path, options.fetch(:defaults), protocol:)
            options.fetch(:languages).each do |language, language_options|
              validate_variant_options!(path, language_options, protocol:, language:)
            end
          end
        end

        private

        def validate_variant_options!(path, options, protocol: nil, language: nil)
          options.each do |name, value|
            validate_string_option!(
              path,
              name,
              value,
              protocol:,
              language:,
              allow_nil: false,
              allow_blank: !%i[from subject].include?(name),
              limit: TRANSLATION_ATTRIBUTE_LIMIT
            )
          end
        end

        def validate_string_option!(path, name, value, allow_nil:, allow_blank:, limit:, protocol: nil, language: nil)
          scope = protocol ? " for protocol #{protocol.inspect}" : ''
          if language
            scope = protocol ? "#{scope} and language #{language.inspect}" : " for language #{language.inspect}"
          end
          return if value.nil? && allow_nil

          unless value.is_a?(String)
            raise InvalidTemplate, "#{path}: #{name}#{scope} must be a string"
          end

          if !allow_blank && value.strip.empty?
            raise InvalidTemplate, "#{path}: #{name}#{scope} cannot be blank"
          end

          return if value.length <= limit

          raise InvalidTemplate, "#{path}: #{name}#{scope} is longer than #{limit} characters"
        end
      end

      # Parse the deliberately small metadata DSL without executing Ruby. The
      # source still looks like meta.rb for template authors, but calls,
      # constants, interpolation and every other Ruby construct are rejected.
      class MetaParser
        TEMPLATE_OPTIONS = %w[label user_visibility from reply_to return_path subject].freeze
        EMAIL_OPTIONS = %w[from reply_to return_path subject].freeze

        def initialize(path, source)
          @path = path
          @source = source
          @string_literals = scan_string_literals
          @string_index = 0
        end

        def parse
          tree = Ripper.sexp(@source)
          invalid!('invalid Ruby syntax') unless tree
          invalid!('metadata must contain one template block') unless tree[0] == :program

          statements = statements_from(tree[1])
          invalid!('metadata must contain one template block') unless statements.length == 1

          name, args, body = parse_block(statements.first)
          invalid!('metadata must contain one template block') unless name == 'template'
          invalid!('template accepts zero or one ID') unless args.length <= 1
          if args.any? && !args.first.is_a?(Symbol) && !args.first.is_a?(String)
            invalid!('template ID must be a symbol or string')
          end

          meta = Meta.new(args.first)
          parse_template_body(meta, body)
          invalid!('unsupported string literal') unless @string_index == @string_literals.length
          meta
        rescue InvalidTemplate
          raise
        rescue StandardError => e
          invalid!("#{e.class}: #{e.message.lines.first.to_s.strip}")
        end

        private

        def parse_template_body(meta, statements)
          statements_from(statements).each do |statement|
            if statement[0] == :method_add_block
              name, args, body = parse_block(statement)
              case name
              when 'lang'
                language = parse_language(args)
                options = parse_variant_options(body, protocol: 'email')
                meta.add_language(language, options, path: @path)
              when 'protocol'
                protocol = parse_protocol(args)
                defaults, languages = parse_protocol_body(body, protocol:)
                meta.add_protocol(protocol, defaults, languages, path: @path)
              else
                invalid!('only lang and protocol blocks are allowed inside template')
              end
            else
              option_name, option_args = parse_call(statement)
              unless TEMPLATE_OPTIONS.include?(option_name)
                invalid!("unsupported template option #{option_name.inspect}")
              end
              invalid!("#{option_name} requires one argument") unless option_args.length == 1

              if Meta::TEMPLATE_OPTS.include?(option_name.to_sym)
                meta.assign_template(option_name.to_sym, option_args.first)
              else
                meta.assign_variant(option_name.to_sym, option_args.first)
              end
            end
          end
        end

        def parse_protocol_body(body, protocol:)
          defaults = {}
          languages = {}

          statements_from(body).each do |statement|
            if statement[0] == :method_add_block
              name, args, language_body = parse_block(statement)
              invalid!('only lang blocks are allowed inside protocol') unless name == 'lang'

              language = NotificationTemplates.normalize_language(parse_language(args), path: @path)
              if languages.has_key?(language)
                invalid!("language #{language.inspect} is declared more than once for protocol #{protocol.inspect}")
              end

              languages[language] = parse_variant_options(language_body, protocol:)
            else
              option_name, option_args = parse_call(statement)
              assign_variant_option(defaults, option_name, option_args, protocol:)
            end
          end

          [defaults, languages]
        end

        def parse_variant_options(body, protocol:)
          statements_from(body).each_with_object({}) do |statement, options|
            invalid!('nested blocks are not allowed inside lang') if statement[0] == :method_add_block

            option_name, option_args = parse_call(statement)
            assign_variant_option(options, option_name, option_args, protocol:)
          end
        end

        def assign_variant_option(options, option_name, option_args, protocol:)
          allowed = PROTOCOL_OPTIONS.fetch(protocol).map(&:to_s)
          invalid!("unsupported #{protocol} option #{option_name.inspect}") unless allowed.include?(option_name)
          invalid!("#{option_name} requires one argument") unless option_args.length == 1
          if options.has_key?(option_name.to_sym)
            invalid!("#{option_name} is declared more than once for protocol #{protocol.inspect}")
          end

          variant_options = VariantOptions.new(protocol:)
          variant_options.assign(option_name.to_sym, option_args.first)
          options.update(variant_options.opts)
        end

        def parse_language(args)
          invalid!('lang requires one symbol or string argument') unless args.length == 1
          unless args.first.is_a?(Symbol) || args.first.is_a?(String)
            invalid!('lang requires one symbol or string argument')
          end

          args.first
        end

        def parse_protocol(args)
          invalid!('protocol requires one symbol or string argument') unless args.length == 1
          unless args.first.is_a?(Symbol) || args.first.is_a?(String)
            invalid!('protocol requires one symbol or string argument')
          end

          protocol = args.first.to_s
          invalid!("unsupported template protocol #{protocol.inspect}") unless PROTOCOLS.include?(protocol)
          protocol
        end

        def parse_block(node)
          invalid!('unsupported metadata statement') unless node.is_a?(Array) && node[0] == :method_add_block

          name, args = parse_call(node[1])
          block = node[2]
          invalid!('only do/end blocks are supported') unless block.is_a?(Array) && block[0] == :do_block
          invalid!('block parameters are not supported') unless block[1].nil?

          body = block[2]
          unless body.is_a?(Array) && body[0] == :bodystmt && body.drop(2).all?(&:nil?)
            invalid!('rescue, else and ensure are not supported')
          end

          [name, args, body[1]]
        end

        def parse_call(node)
          invalid!('unsupported metadata statement') unless node.is_a?(Array)

          case node[0]
          when :command
            [identifier(node[1]), parse_arguments(node[2])]
          when :method_add_arg
            callable = node[1]
            invalid!('method receivers are not supported') unless callable.is_a?(Array) && callable[0] == :fcall

            [identifier(callable[1]), parse_arguments(node[2])]
          else
            invalid!('unsupported metadata statement')
          end
        end

        def parse_arguments(node)
          return [] if node == [] || node.nil?
          return parse_arguments(node[1]) if node.is_a?(Array) && node[0] == :arg_paren

          unless node.is_a?(Array) && node[0] == :args_add_block && node[2] == false
            invalid!('unsupported arguments')
          end

          node[1].map { |argument| parse_literal(argument) }
        end

        def parse_literal(node)
          invalid!('metadata values must be literal strings, symbols or booleans') unless node.is_a?(Array)

          case node[0]
          when :string_literal
            value = @string_literals[@string_index]
            invalid!('unsupported string literal') unless value

            @string_index += 1
            value
          when :symbol_literal
            symbol = node.dig(1, 1)
            unless symbol.is_a?(Array) && %i[@ident @const].include?(symbol[0])
              invalid!('symbols must use identifier names')
            end

            symbol[1].to_sym
          when :var_ref
            keyword = node[1]
            return true if keyword.is_a?(Array) && keyword[0] == :@kw && keyword[1] == 'true'
            return false if keyword.is_a?(Array) && keyword[0] == :@kw && keyword[1] == 'false'

            invalid!('only true and false constants are supported')
          else
            invalid!('metadata values must be literal strings, symbols or booleans')
          end
        end

        def statements_from(node)
          Array(node).reject { |statement| statement == [:void_stmt] }
        end

        def identifier(node)
          invalid!('expected an unqualified method name') unless node.is_a?(Array) && node[0] == :@ident

          node[1]
        end

        def scan_string_literals
          tokens = Ripper.lex(@source)
          values = []
          index = 0

          while index < tokens.length
            _position, event, token = tokens[index]
            unless event == :on_tstring_beg
              index += 1
              next
            end

            delimiter = token
            invalid!('only single- and double-quoted strings are supported') unless %w[' "].include?(delimiter)
            raw = +''
            index += 1

            while index < tokens.length && tokens[index][1] != :on_tstring_end
              unless tokens[index][1] == :on_tstring_content
                invalid!('string interpolation and dynamic strings are not supported')
              end

              raw << tokens[index][2]
              index += 1
            end

            invalid!('unterminated string literal') if index == tokens.length
            values << decode_string(delimiter, raw)
            index += 1
          end

          values
        end

        def decode_string(delimiter, raw)
          if delimiter == "'"
            raw.gsub(/\\(['\\])/) { Regexp.last_match(1) }
          else
            %("#{raw}").undump
          end
        rescue RuntimeError => e
          invalid!("invalid string escape: #{e.message}")
        end

        def invalid!(message)
          raise InvalidTemplate, "#{@path}: #{message}"
        end
      end

      class DirectoryVariant
        attr_reader :protocol, :language

        def initialize(template, protocol, language, files)
          @template = template
          @protocol = protocol
          @language = language
          @content = files.transform_values do |path|
            File.read(path, encoding: Encoding::UTF_8)
          end

          if @content.has_key?(:subject)
            subject = content(:subject)
            if subject.strip.empty?
              raise InvalidTemplate, "#{files[:subject]}: subject cannot be blank"
            elsif subject.length > TRANSLATION_ATTRIBUTE_LIMIT
              raise InvalidTemplate,
                    "#{files[:subject]}: subject is longer than #{TRANSLATION_ATTRIBUTE_LIMIT} characters"
            end
          end

          case protocol
          when 'email'
            return if @content.has_key?(:text) || @content.has_key?(:html)

            raise InvalidTemplate,
                  "#{template.path}/email: language #{language.inspect} has no text or HTML body"
          when 'telegram', 'sms'
            return if @content.has_key?(:text)

            raise InvalidTemplate,
                  "#{template.path}/#{protocol}: language #{language.inspect} has no text body"
          end
        end

        def content(format)
          content = @content[format]
          return content.chomp if format == :subject && content
          return DEFAULT_TELEGRAM_HTML if format == :html && protocol == 'telegram' && content.nil?

          content
        end

        def options
          @template.variant_options(protocol, language)
        end
      end

      class DirectoryTemplate
        attr_reader :path, :name, :id, :variants

        def initialize(path, root:)
          @path = path
          @root = root
          @name = File.basename(path)
          @variants = []

          validate_name!
          validate_entries!
          load_meta!
          load_variants!
        end

        def template_options
          @meta.template_opts
        end

        def variant_options(protocol, language)
          @meta.variant_options(protocol, language)
        end

        private

        def validate_name!
          unless TEMPLATE_NAME_PATTERN.match?(name)
            raise InvalidTemplate, "#{path}: invalid template directory name #{name.inspect}"
          end

          return if name.length <= TEMPLATE_ATTRIBUTE_LIMIT

          raise InvalidTemplate, "#{path}: template name is longer than #{TEMPLATE_ATTRIBUTE_LIMIT} characters"
        end

        def validate_entries!
          ensure_within_root!(path)

          allowed = PROTOCOLS + %w[meta.rb]
          unexpected = Dir.children(path).sort - allowed
          unless unexpected.empty?
            raise InvalidTemplate, "#{path}: unsupported entry #{unexpected.first.inspect}"
          end

          meta_path = File.join(path, 'meta.rb')
          raise InvalidTemplate, "#{meta_path}: file does not exist" unless File.file?(meta_path)

          ensure_within_root!(meta_path)
          PROTOCOLS.each do |protocol|
            protocol_path = File.join(path, protocol)
            ensure_within_root!(protocol_path) if File.exist?(protocol_path) || File.symlink?(protocol_path)
          end
        end

        def load_meta!
          meta_path = File.join(path, 'meta.rb')
          source = File.read(meta_path, encoding: Encoding::UTF_8)
          @meta = MetaParser.new(meta_path, source).parse
          @meta.validate!(meta_path)
          @id = @meta.id || name
        end

        def load_variants!
          files = {}
          language_spellings = Hash.new { |hash, protocol| hash[protocol] = {} }

          PROTOCOLS.each do |protocol|
            protocol_path = File.join(path, protocol)
            next unless File.directory?(protocol_path)

            entries = Dir.children(protocol_path).sort
            raise InvalidTemplate, "#{protocol_path}: no #{protocol} templates found" if entries.empty?

            entries.each do |entry|
              file_path = File.join(protocol_path, entry)
              ensure_within_root!(file_path)
              raise InvalidTemplate, "#{file_path}: expected an ERB file" unless File.file?(file_path)

              match = VARIANT_FILE_PATTERN.match(entry)
              raise InvalidTemplate, "#{file_path}: unsupported #{protocol} template filename" unless match

              format = match[:format]
              unless PROTOCOL_FORMATS.fetch(protocol).include?(format)
                raise InvalidTemplate, "#{file_path}: unsupported #{protocol} template format #{format.inspect}"
              end

              raw_language = match[:language]
              language = NotificationTemplates.normalize_language(raw_language, path: file_path)
              spellings = language_spellings[protocol]
              if spellings.has_key?(language) && spellings[language] != raw_language
                raise InvalidTemplate,
                      "#{file_path}: language collides with #{spellings[language].inspect} ignoring case"
              end
              spellings[language] = raw_language
              format = format.to_sym
              key = [protocol, language]
              files[key] ||= {}
              if files[key].has_key?(format)
                raise InvalidTemplate, "#{file_path}: duplicate #{format} template for language #{language.inspect}"
              end

              source = File.read(file_path, encoding: Encoding::UTF_8)
              compile_erb!(file_path, source)
              validate_telegram_html!(file_path, source) if protocol == 'telegram' && format == :html
              files[key][format] = file_path
            end
          end

          raise InvalidTemplate, "#{path}: no notification template variants found" if files.empty?

          @variants = files.map do |(protocol, language), variant_files|
            DirectoryVariant.new(self, protocol, language, variant_files)
          end

          @variants.each do |variant|
            subject = variant.options[:subject]
            compile_erb!(File.join(path, 'meta.rb'), subject) if subject
          end
        end

        def ensure_within_root!(entry)
          root = File.realpath(@root)
          resolved = File.realpath(entry)
          return if resolved == root || resolved.start_with?("#{root}/")

          raise InvalidTemplate, "#{entry}: symbolic link points outside the template tree"
        rescue Errno::ENOENT, Errno::ELOOP => e
          raise InvalidTemplate, "#{entry}: #{first_line(e.message)}"
        end

        def compile_erb!(source_path, source)
          RubyVM::InstructionSequence.compile(
            ERB.new(source, trim_mode: '-').src,
            source_path
          )
        rescue SyntaxError => e
          raise InvalidTemplate, "#{source_path}: invalid ERB: #{first_line(e.message)}"
        end

        def validate_telegram_html!(source_path, source)
          markup = source.gsub(/<%.*?%>/m, '')
          tags = markup.scan(%r{</?([a-zA-Z][\w-]*)(?:\s[^>]*)?>}).flatten.uniq
          unsupported = tags - TELEGRAM_ALLOWED_HTML_TAGS
          return if unsupported.empty?

          raise InvalidTemplate,
                "#{source_path}: unsupported Telegram HTML tag(s): #{unsupported.join(', ')}"
        end

        def first_line(message)
          message.lines.first.to_s.strip
        end
      end

      class Directory
        attr_reader :path, :templates

        def initialize(path)
          @path = self.class.resolve_path(path)
          @templates = load_templates
        end

        def self.resolve_path(path)
          path = path.to_s
          nested = File.join(path, 'templates')
          resolved = File.directory?(nested) ? nested : path

          raise InvalidTemplate, "#{path}: template directory does not exist" unless File.directory?(resolved)

          resolved
        end

        private

        def load_templates
          templates = Dir.children(path).sort.map do |entry|
            template_path = File.join(path, entry)
            unless File.directory?(template_path)
              raise InvalidTemplate, "#{template_path}: expected a template directory"
            end

            DirectoryTemplate.new(template_path, root: path)
          end

          raise InvalidTemplate, "#{path}: no notification templates found" if templates.empty?

          templates
        end
      end
    end
  end
end
