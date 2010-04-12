require 'optparse'
require 'logger'

module NewRelic::IA

  class InitError < StandardError;  end
  
  class CLI
    
    LOGFILE = "newrelic_ia.log"
    @log = Logger.new(STDOUT)
    
    class << self
      attr_accessor :log
      def level= l
        @log.level = l      
      end
      
      # Run the command line args.  Return nil if running
      # or an exit status if not.
      def execute(stdout, arguments=[])
        @aspects = []
        @log = Logger.new LOGFILE
        @log_level = Logger::INFO
        parser = OptionParser.new do |opts|
          opts.banner = <<-BANNER.gsub(/^ */,'')

          Monitor different aspects of your environment with New Relic RPM.  

          Usage: #{File.basename($0)} [ options ] aspect, aspect.. 

          aspect: one or more of 'memcached', 'iostat' or 'disk' (more to come)
        BANNER
          opts.separator ""
          opts.on("-a", "--all",
                  "use all available aspects") { @aspects = %w[iostat disk memcached] }
          opts.on("-v", "--verbose",
                  "debug output") { @log_level = Logger::DEBUG }
          opts.on("-q", "--quiet",
                  "quiet output") { @log_level = Logger::ERROR }
          opts.on("-e", "--environment=ENV",
                  "use ENV section in newrelic.yml") { |e| @env = e }
          opts.on("--install",
                  "create a default newrelic.yml") { |e| return self.install }
          
          opts.on("-h", "--help",
                  "Show this help message.") { stdout.puts "#{opts}\n"; return 0 }
          begin
            args = opts.parse! arguments
            unless args.empty?
              @aspects = args
            end
          rescue => e
            stdout.puts e
            stdout.puts opts
            return 1
          end
        end
        @aspects.delete_if do |aspect|
          unless self.instance_methods(false).include? aspect
            stdout.puts "Unknown aspect: #{aspect}"
            true
          end
        end
        if @aspects.empty?
          stdout.puts "No aspects specified."
          stdout.puts parser
          return 1
        end
        
        @log.level = @log_level 
        gem 'newrelic_rpm'
        require 'newrelic_rpm'
        NewRelic::Agent.manual_start :log => @log, :env => @env, :enabled => true
        cli = new
        @aspects.each do | aspect |
          cli.send aspect
        end
        return nil
      rescue InitError => e
        stdout.puts e.message
        return 1
      end
      
    end
    # Aspect definitions
    def iostat # :nodoc:
      self.class.log.info "Starting iostat monitor..."
      require 'new_relic/ia/iostat_reader'
      reader = NewRelic::IA::IostatReader.new
      Thread.new { reader.run }
    end
    
    def disk
      self.class.log.info "Starting disk sampler..."
      require 'new_relic/ia/disk_sampler'
      NewRelic::Agent.instance.stats_engine.add_harvest_sampler NewRelic::IA::DiskSampler.new    
    end
    
    def memcached
      self.class.log.info "Starting memcached sampler..."
      require 'new_relic/ia/memcached_sampler'
      NewRelic::Agent.instance.stats_engine.add_harvest_sampler NewRelic::IA::MemcachedSampler.new
    end

    private
    
    def self.install
      require 'new_relic/command.rb'
      cmd = NewRelic::Command::Install.new \
      :src_file => File.join(File.dirname(__FILE__), "newrelic.yml"),
      :generated_for_user => "Generated on #{Time.now.strftime('%b %d, %Y')}, from version #{NewRelic::IA::VERSION}"
      cmd.run 
      0 # normal
    rescue NewRelic::Command::CommandFailure => e
      $stderr.puts e.message
      1 # error
    def self.require_newrelic_rpm
      begin
        require 'newrelic_rpm'
      rescue Exception => e
        begin
          require 'rubygems' unless ENV['NO_RUBYGEMS']
          require 'newrelic_rpm'
        rescue LoadError
          $stderr.puts "Unable to load required gem newrelic_rpm"
          $stderr.puts "Try `gem install newrelic_rpm`"
          Kernel.exit 1
        end
      end
    end
    
    end
  end
end
