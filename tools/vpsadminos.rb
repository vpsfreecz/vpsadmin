require 'json'
require 'open3'

module Vpsadminos
  class Error < StandardError; end

  module_function

  def repo_root
    @repo_root ||= File.realpath(File.join(__dir__, '..'))
  end

  def local_checkout?
    !ENV.fetch('VPSADMINOS_PATH', '').empty?
  end

  def local_path
    path = ENV.fetch('VPSADMINOS_PATH', '')
    return nil if path.empty?

    File.realpath(path)
  rescue Errno::ENOENT
    raise Error, "VPSADMINOS_PATH does not exist: #{path}"
  end

  def flake_input_path
    stdout, stderr, status = Open3.capture3(
      'nix', 'flake', 'archive', '--json', repo_root
    )

    unless status.success?
      detail = stderr.strip
      message = "Unable to resolve vpsadminos flake input from #{repo_root}"
      message += ": #{detail}" unless detail.empty?

      raise Error, message
    end

    path = JSON.parse(stdout).dig('inputs', 'vpsadminos', 'path')

    if path.nil? || path.empty?
      raise Error,
            'nix flake archive did not return inputs.vpsadminos.path for ' \
            "#{repo_root}"
    end

    File.realpath(path)
  rescue Errno::ENOENT
    raise Error,
          'Unable to run `nix flake archive`; install nix or set VPSADMINOS_PATH'
  rescue JSON::ParserError => e
    raise Error, "Unable to parse `nix flake archive` output: #{e.message}"
  end

  def source_path
    local_path || flake_input_path
  end

  def version
    version_path = File.join(source_path, '.version')
    "#{File.read(version_path).strip}.0"
  rescue Errno::ENOENT
    raise Error, "vpsAdminOS version not found at '#{version_path}'"
  end

  def export_env!
    ENV['VPSADMINOS_PATH'] = source_path
    ENV['VPSADMINOS_GEM_VERSION'] ||= version
  end
end
