# frozen_string_literal: true

require 'fileutils'
require 'tmpdir'

RSpec.describe VpsAdmin::API::NotificationTemplates do
  def write_template(root, name: 'example_template', meta: default_meta, files: default_files)
    path = File.join(root, name)
    FileUtils.mkdir_p(File.join(path, 'email'))
    File.write(File.join(path, 'meta.rb'), meta)
    files.each do |name, content|
      File.write(File.join(path, 'email', name), content)
    end
    path
  end

  def default_meta
    <<~RUBY
      template :user_create do
        label 'Example template'

        lang :en do
          from 'from@example.test'
        end
      end
    RUBY
  end

  def default_files
    {
      'en.subject.erb' => "Subject for <%= @user.login %>\n",
      'en.text.erb' => 'Text for <%= @user.login %>'
    }
  end

  it 'loads metadata and email variants' do
    Dir.mktmpdir do |dir|
      template_path = write_template(dir)
      File.write(File.join(template_path, 'email', 'en.html.erb'), '<p>HTML</p>')

      template = described_class::Directory.new(dir).templates.first
      variant = template.variants.first

      expect(template).to have_attributes(
        name: 'example_template',
        id: :user_create,
        template_options: { label: 'Example template' }
      )
      expect(variant).to have_attributes(language: 'en')
      expect(variant.options).to eq(from: 'from@example.test')
      expect(variant.content(:subject)).to eq('Subject for <%= @user.login %>')
      expect(variant.content(:text)).to eq('Text for <%= @user.login %>')
      expect(variant.content(:html)).to eq('<p>HTML</p>')
    end
  end

  it 'accepts a package with a templates subdirectory' do
    Dir.mktmpdir do |dir|
      templates = File.join(dir, 'templates')
      FileUtils.mkdir_p(templates)
      write_template(templates)

      expect(described_class::Directory.new(dir).templates.map(&:name)).to eq(['example_template'])
    end
  end

  it 'uses a metadata subject when no subject file exists' do
    Dir.mktmpdir do |dir|
      write_template(
        dir,
        meta: <<~RUBY,
          template do
            lang :en do
              subject 'Metadata subject <%= @user.login %>'
            end
          end
        RUBY
        files: { 'en.text.erb' => 'Text body' }
      )

      variant = described_class::Directory.new(dir).templates.first.variants.first
      expect(variant.options[:subject]).to eq('Metadata subject <%= @user.login %>')
    end
  end

  it 'reads template files as UTF-8 regardless of the process locale' do
    original_encoding = Encoding.default_external
    Encoding.default_external = Encoding::US_ASCII

    Dir.mktmpdir do |dir|
      write_template(
        dir,
        meta: "template do\n  label 'Česká šablona'\nend\n",
        files: { 'cs.text.erb' => 'České tělo' }
      )

      template = described_class::Directory.new(dir).templates.first
      expect(template.template_options[:label]).to eq('Česká šablona')
      expect(template.variants.first.content(:text)).to eq('České tělo')
    end
  ensure
    Encoding.default_external = original_encoding
  end

  it 'rejects legacy body paths' do
    Dir.mktmpdir do |dir|
      path = write_template(dir)
      File.write(File.join(path, 'en.plain.erb'), 'Legacy body')

      expect do
        described_class::Directory.new(dir)
      end.to raise_error(described_class::InvalidTemplate, /unsupported entry "en\.plain\.erb"/)
    end
  end

  it 'rejects unknown protocols' do
    Dir.mktmpdir do |dir|
      path = write_template(dir)
      FileUtils.mkdir_p(File.join(path, 'telegram'))

      expect do
        described_class::Directory.new(dir)
      end.to raise_error(described_class::InvalidTemplate, /unsupported entry "telegram"/)
    end
  end

  it 'rejects variants without a text or HTML body' do
    Dir.mktmpdir do |dir|
      write_template(dir, files: { 'en.subject.erb' => 'Subject only' })

      expect do
        described_class::Directory.new(dir)
      end.to raise_error(described_class::InvalidTemplate, /has no text or HTML body/)
    end
  end

  it 'reports invalid ERB paths' do
    Dir.mktmpdir do |dir|
      write_template(dir, files: { 'en.text.erb' => '<% if true %>' })

      expect do
        described_class::Directory.new(dir)
      end.to raise_error(described_class::InvalidTemplate, %r{email/en\.text\.erb: invalid ERB})
    end
  end

  it 'rejects invalid metadata values' do
    Dir.mktmpdir do |dir|
      write_template(
        dir,
        meta: <<~RUBY
          template do
            label 42
          end
        RUBY
      )

      expect do
        described_class::Directory.new(dir)
      end.to raise_error(described_class::InvalidTemplate, /metadata values must be literal/)
    end
  end

  it 'parses metadata without executing Ruby' do
    Dir.mktmpdir do |dir|
      marker = File.join(dir, 'executed')
      write_template(
        dir,
        meta: <<~RUBY
          File.write(#{marker.inspect}, 'executed')

          template do
            label 'Example template'
          end
        RUBY
      )

      expect do
        described_class::Directory.new(dir)
      end.to raise_error(described_class::InvalidTemplate, /one template block/)
      expect(File).not_to exist(marker)
    end
  end

  it 'rejects values that cannot be persisted' do
    invalid_cases = [
      ["template do\n  label '   '\nend\n", default_files, /label cannot be blank/],
      ["template do\n  label '#{'a' * 101}'\nend\n", default_files, /label is longer than 100/],
      ["template :#{'a' * 101} do\nend\n", default_files, /template_id is longer than 100/],
      [
        "template do\n  lang :en do\n    from ' '\n  end\nend\n",
        default_files,
        /from for language "en" cannot be blank/
      ],
      [
        "template do\n  lang :en do\n    from '#{'a' * 256}'\n  end\nend\n",
        default_files,
        /from for language "en" is longer than 255/
      ],
      [default_meta, { 'en.subject.erb' => "\n", 'en.text.erb' => 'Body' }, /subject cannot be blank/],
      [
        default_meta,
        { 'en.subject.erb' => 's' * 256, 'en.text.erb' => 'Body' },
        /subject is longer than 255/
      ],
      [default_meta, { 'en-US.text.erb' => 'Body' }, /unsupported email template filename/]
    ]

    invalid_cases.each do |meta, files, error|
      Dir.mktmpdir do |dir|
        write_template(dir, meta:, files:)

        expect do
          described_class::Directory.new(dir)
        end.to raise_error(described_class::InvalidTemplate, error)
      end
    end

    Dir.mktmpdir do |dir|
      write_template(dir, name: 'a' * 101)

      expect do
        described_class::Directory.new(dir)
      end.to raise_error(described_class::InvalidTemplate, /template name is longer than 100/)
    end
  end

  it 'normalizes language codes and rejects case-insensitive collisions' do
    Dir.mktmpdir do |dir|
      write_template(
        dir,
        meta: "template do\n  lang :EN do\n    from 'from@example.test'\n  end\nend\n",
        files: { 'EN.text.erb' => 'Body' }
      )

      variant = described_class::Directory.new(dir).templates.first.variants.first
      expect(variant).to have_attributes(language: 'en')
      expect(variant.options).to eq(from: 'from@example.test')
    end

    Dir.mktmpdir do |dir|
      path = write_template(dir)
      File.write(File.join(path, 'email', 'EN.html.erb'), '<p>Body</p>')

      expect do
        described_class::Directory.new(dir)
      end.to raise_error(described_class::InvalidTemplate, /collides with "(?:en|EN)" ignoring case/)
    end

    Dir.mktmpdir do |dir|
      write_template(
        dir,
        meta: <<~RUBY
          template do
            lang :en do
            end
            lang :EN do
            end
          end
        RUBY
      )

      expect do
        described_class::Directory.new(dir)
      end.to raise_error(described_class::InvalidTemplate, /language "en" is declared more than once/)
    end
  end

  it 'allows relative symlinks within the template tree' do
    Dir.mktmpdir do |dir|
      path = write_template(dir)
      File.symlink('en.text.erb', File.join(path, 'email', 'cs.text.erb'))

      variants = described_class::Directory.new(dir).templates.first.variants
      expect(variants.map(&:language)).to contain_exactly('cs', 'en')
    end
  end

  it 'rejects symlinks outside the template tree' do
    Dir.mktmpdir do |dir|
      path = write_template(dir)
      outside = File.join(dir, '..', "#{File.basename(dir)}-outside.erb")
      File.write(outside, 'Outside')
      File.symlink(outside, File.join(path, 'email', 'cs.text.erb'))

      expect do
        described_class::Directory.new(dir)
      end.to raise_error(described_class::InvalidTemplate, /symbolic link points outside/)
    ensure
      FileUtils.rm_f(outside) if outside
    end
  end
end
