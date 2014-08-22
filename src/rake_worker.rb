# Copyright (c) 2013 MaestroDev.  All rights reserved.
require 'maestro_plugin'

require 'maestro_shell'
require 'ruby_helper'

module MaestroDev
  module Plugin
  
    class RakeWorker < Maestro::MaestroWorker
      include Maestro::Plugin::RubyHelper
  
      def execute
        validate_parameters
  
        shell = Maestro::Util::Shell.new
        command = create_command
        shell.create_script(command)
  
        write_output("\nRunning command:\n----------\n#{command.chomp}\n----------\n")
        exit_code = shell.run_script_with_delegate(self, :on_output)
        output = shell.output
        extract_test_results(output)

        raise PluginError, "Error running rake tasks '#{@tasks.empty? ? '[default]' : @tasks}'" unless exit_code.success?
      end
  
      def on_output(text)
        write_output(text, :buffer => true)
      end
  
      ###########
      # PRIVATE #
      ###########
      private
  
      def valid_executable?(executable)
        Maestro::Util::Shell.run_command("#{executable} --version")[0].success?
      end
  
      def validate_parameters
        errors = []

        @rake_executable = get_field('rake_executable', 'rake')
  
        @use_rvm = get_boolean_field('use_rvm')
        @rvm_executable = get_field('rvm_executable', 'rvm')
  
        @ruby_version = get_field('ruby_version', '')
  
        @rubygems_version = get_field('rubygems_version', '')
  
        @use_bundle = get_boolean_field('use_bundle')
        @bundler_version = get_field('bundler_version')
        @bundle_executable = get_field('bundle_executable', (@bundler_version.nil? || @bundler_version.empty?) ? "bundle" : "bundle _#{@bundler_version}_")

        @environment = get_field('environment', '')
        @env = @environment.empty? ? "" : "#{Maestro::Util::Shell::ENV_EXPORT_COMMAND} #{@environment.gsub(/(&&|[;&])\s*$/, '')} && "
        errors << 'rvm not installed' if @use_rvm && !valid_executable?(@rvm_executable)
  
        @tasks = get_field('tasks', '')
        @gems = get_field('gems', [])
  
        @path = get_field('path') || get_field('scm_path')
        errors << 'missing field path' if @path.nil?
        errors << "not found path '#{@path}'" if !@path.nil? && !File.exist?(@path)
  
        update_ruby_rubygems
  
        if @use_rvm
          errors << "Requested Ruby version #{@ruby_version} not available" unless @ruby_version.empty? || (@installed_ruby_version && @ruby_version == @installed_ruby_version)
          errors << "Requested RubyGems version #{@rubygems_version} not available" unless @rubygems_version.empty? || (@installed_rubygems_version && @rubygems_version == @installed_rubygems_version)

          # Set a default ruby version to use if rvm is specified and no version.  Basically we will use default version configured for rvm
          if @ruby_version.empty?
            @ruby_version = 'default'
            write_output("WARNING: No version of ruby specified for RVM, using 'default'.  Note that this may behave differently depending on the default version configured in RVM.  It is recommended to specify the actual version required.\n")
          end
        end

        # this check wasn't done previousy
        # We need to do after rvm check, coz that might install rvm and that will affect whether these two will work
        errors << 'bundle not installed' if @use_bundle && !valid_executable?("#{ruby_prefix} #{@bundle_executable}")
        errors << 'rake not installed' unless valid_executable?("#{ruby_prefix} #{@rake_executable}")
  
        process_tasks_field
        process_gems_field
  
        if !errors.empty?
          raise ConfigError, "Configuration errors: #{errors.join(', ')}"
        end
      end
  
      def process_gems_field
        if !@gems.empty? && is_json(@gems)
          @gems = JSON.parse(@gems) if @gems.is_a? String
        end
      
        if !@gems.is_a?(Array)
          Maestro.log.warn "Invalid Format For gems Field #{@gems} - ignoring [#{@gems.class.name}] #{@gems}"
          @gems = nil
        end
      end
    
      def process_tasks_field
        begin
          if is_json(@tasks)
            @tasks = JSON.parse(@tasks) if @tasks.is_a? String
          end
        rescue Exception  
        end
        
        if @tasks.is_a? Array
          @tasks = @tasks.join(' ')
        end
      end

      def rvm_prefix
        @use_rvm ? "#{script_prefix} rvm use #{@ruby_version} && " : ''
      end

      def ruby_prefix
        "#{Maestro::Util::Shell::ENV_EXPORT_COMMAND} RUBYOPT=\n#{@env} #{rvm_prefix}"
      end
  
      def create_command
        # TODO consider something in standard ruby such as system({"MYVAR" => "42"}, "echo $MYVAR")
        if @use_bundle
          # ensure we are not overriding a BUNDLE_WITHOUT variable set in the fields
          if @environment.include?("BUNDLE_WITHOUT=")
            bundle_without = nil
          else
            # ENV Var is just one way to get bundle to do without... if you 'bundle config without....' it is stickier and is in
            # the .bundle dir.
            # rake seems to use this more official way of setting... and even though it does clear the .bundle dir on a clean
            # that doesn't help if rake isn't installed!
            bundle_without = "#{@bundle_executable} config --delete without && #{Maestro::Util::Shell::ENV_EXPORT_COMMAND} BUNDLE_WITHOUT=''"
          end
          bundle = "#{Maestro::Util::Shell::ENV_EXPORT_COMMAND} BUNDLE_GEMFILE=#{@path}/Gemfile #{bundle_without ? "&& #{bundle_without} &&" : ''} #{@bundle_executable} install && #{@bundle_executable} exec"
        end
        
        if @gems && !@gems.empty?
          Maestro.log.debug "Install Gems #{@gems.join(', ')}"
          gems_script = ''
          @gems.each do |gem_name|
            gems_script += "(gem list #{gem_name} -i || gem install #{gem_name} --no-ri --no-rdoc)"
          end
        end
  
        shell_command = "cd #{@path} && #{ruby_prefix} #{@gems && !@gems.empty? ? "#{gems_script} &&" : ''} #{@use_bundle ? "#{bundle} " : ''} #{@rake_executable} --trace #{@tasks}"
  
        set_field('command', shell_command)

        Maestro.log.debug("Running #{shell_command}")
        shell_command
      end
  
      def extract_test_results(output)      
        # Post-process output to try to gather some semi-useful info (like, how many tests were run, etc)
        # I figure this is going to be pretty version-specific
        tests = output.scan(/\n\*\* Execute (spec(?:\:\w*)?)(.*)Finished in (?:(\d*(?:\.\d+)?) minutes )?(\d*(?:\.\d+)?) seconds\n*(\d+) examples, (\d+) failures\n/m)
        
        if tests and !tests.empty?
          Maestro.log.info "Found #{tests.length} test blocks"
          test_meta = []
  
          tests.each do |test|
            # [0] = test name
            # [1] = test output  -- we can run further regexes to extract failing tests if we want
            # [2] = duration (mins - optional - newer rake)
            # [3] = duration (seconds)
            # [4] = # tests
            # [5] = # failures

            test[2] = '0' if test[2].nil?
            test_name = test[0]
            duration = test[2].to_i * 60 + test[3].to_i
            test_count = test[4].to_i
            fail_count = test[5].to_i
            pass_count = test_count - fail_count
            test_meta << { :spec => test_name, :duration => duration, :tests => test_count, :passed => pass_count, :failures => fail_count }
            write_output("\nFound test results: spec: #{test_name}, duration: #{duration}, tests: #{test_count}, passed: #{pass_count}, failures: #{fail_count}", :buffer => true)
          end
          
          save_output_value('tests', test_meta)
        else
          write_output("\nNo test results found", :buffer => true)
        end
      end
    end
  end
end
