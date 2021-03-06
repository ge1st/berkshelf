require 'buff/extensions'
require 'digest/md5'
require 'forwardable'
require 'json'
require 'pathname'
require 'ridley'
require 'solve'
require 'thor'
require 'tmpdir'
require 'uri'

JSON.create_id = nil

require_relative 'berkshelf/core_ext'
require_relative 'berkshelf/thor_ext'

module Berkshelf
  require_relative 'berkshelf/version'
  require_relative 'berkshelf/errors'
  require_relative 'berkshelf/mixin'

  DEFAULT_FILENAME = 'Berksfile'.freeze

  class << self
    include Berkshelf::Mixin::Logging

    attr_writer :berkshelf_path
    attr_accessor :ui
    attr_accessor :logger

    # @return [Pathname]
    def root
      @root ||= Pathname.new(File.expand_path('../', File.dirname(__FILE__)))
    end

    # @return [Thor::Shell::Color, Thor::Shell::Basic]
    #   A basic shell on Windows, colored everywhere else
    def ui
      @ui ||= Thor::Base.shell.new
    end

    # Returns the filepath to the location Berkshelf will use for
    # storage; temp files will go here, Cookbooks will be downloaded
    # to or uploaded from here. By default this is '~/.berkshelf' but
    # can be overridden by specifying a value for the ENV variable
    # 'BERKSHELF_PATH'.
    #
    # @return [String]
    def berkshelf_path
      @berkshelf_path || ENV['BERKSHELF_PATH'] || File.expand_path('~/.berkshelf')
    end

    # The Berkshelf configuration.
    #
    # @return [Berkshelf::Config]
    def config
      Berkshelf::Config.instance
    end

    # @param [Berkshelf::Config]
    def config=(config)
      Berkshelf::Config.set_config(config)
    end

    # The Chef configuration file.
    #
    # @return [Ridley::Chef::Config]
    def chef_config
      @chef_config ||= Ridley::Chef::Config.new(ENV['BERKSHELF_CHEF_CONFIG'])
    end

    # @param [Ridley::Chef::Config]
    def chef_config=(config)
      @chef_config = config
    end

    # Initialize the filepath for the Berkshelf path..
    def initialize_filesystem
      FileUtils.mkdir_p(berkshelf_path, mode: 0755)

      unless File.writable?(berkshelf_path)
        raise InsufficientPrivledges, "You do not have permission to write to '#{berkshelf_path}'!" +
          " Please either chown the directory or use a different filepath."
      end
    end

    # @return [String]
    def tmp_dir
      File.join(berkshelf_path, 'tmp')
    end

    # Creates a temporary directory within the Berkshelf path
    #
    # @return [String]
    #   path to the created temporary directory
    def mktmpdir
      FileUtils.mkdir_p(tmp_dir)
      Dir.mktmpdir(nil, tmp_dir)
    end

    # @return [Berkshelf::CookbookStore]
    def cookbook_store
      CookbookStore.instance
    end

    # Get the appropriate Formatter object based on the formatter
    # classes that have been registered.
    #
    # @return [~Formatter]
    def formatter
      @formatter ||= Formatters::HumanReadable.new
    end

    # @raise [Berkshelf::ChefConnectionError]
    def ridley_connection(options = {}, &block)
      ridley_options               = options.slice(:ssl)

      ridley_options[:server_url]  = options[:server_url] || Berkshelf.config.chef.chef_server_url
      ridley_options[:client_name] = options[:client_name] || Berkshelf.config.chef.node_name
      ridley_options[:client_key]  = options[:client_key] || Berkshelf.config.chef.client_key
      ridley_options[:ssl]         = { verify: (options[:ssl_verify].nil?) ? Berkshelf.config.ssl.verify : options[:ssl_verify]}

      unless ridley_options[:server_url].present?
        raise ChefConnectionError, 'Missing required attribute in your Berkshelf configuration: chef.server_url'
      end

      unless ridley_options[:client_name].present?
        raise ChefConnectionError, 'Missing required attribute in your Berkshelf configuration: chef.node_name'
      end

      unless ridley_options[:client_key].present?
        raise ChefConnectionError, 'Missing required attribute in your Berkshelf configuration: chef.client_key'
      end

      # @todo  Something scary going on here - getting an instance of Kitchen::Logger from test-kitchen
      # https://github.com/opscode/test-kitchen/blob/master/lib/kitchen.rb#L99
      Celluloid.logger = nil unless ENV["DEBUG_CELLULOID"]
      Ridley.open(ridley_options, &block)
    rescue Ridley::Errors::RidleyError => ex
      log_exception(ex)
      raise ChefConnectionError, ex # todo implement
    end

    # Specify the format for output
    #
    # @param [#to_sym] format_id
    #   the ID of the registered formatter to use
    #
    # @example Berkshelf.set_format :json
    #
    # @return [~Formatter]
    def set_format(format_id)
      @formatter = Formatters[format_id].new
    end

    private

      def null_stream
        @null ||= begin
          strm = STDOUT.clone
          strm.reopen(RbConfig::CONFIG['host_os'] =~ /mswin|mingw/ ? 'NUL:' : '/dev/null')
          strm.sync = true
          strm
        end
      end
  end
end

require_relative 'berkshelf/lockfile'
require_relative 'berkshelf/base_generator'
require_relative 'berkshelf/berksfile'
require_relative 'berkshelf/cached_cookbook'
require_relative 'berkshelf/cli'
require_relative 'berkshelf/community_rest'
require_relative 'berkshelf/cookbook_generator'
require_relative 'berkshelf/cookbook_store'
require_relative 'berkshelf/config'
require_relative 'berkshelf/dependency'
require_relative 'berkshelf/downloader'
require_relative 'berkshelf/formatters'
require_relative 'berkshelf/git'
require_relative 'berkshelf/mercurial'
require_relative 'berkshelf/init_generator'
require_relative 'berkshelf/installer'
require_relative 'berkshelf/location'
require_relative 'berkshelf/logger'
require_relative 'berkshelf/resolver'
require_relative 'berkshelf/source'
require_relative 'berkshelf/source_uri'
require_relative 'berkshelf/ui'

Ridley.logger = Berkshelf.logger = Logger.new(STDOUT)
Berkshelf.logger.level = Logger::WARN
