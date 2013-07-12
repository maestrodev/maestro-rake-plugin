# Copyright (c) 2013 MaestroDev.  All rights reserved.
require 'maestro_plugin'

require 'maestro_shell'
require 'ruby_helper'

module MaestroDev

  class ConfigError < StandardError
  end

  class RakeWorker < Maestro::MaestroWorker
    include Maestro::Plugin::RubyHelper

    def execute
      write_output("\nRAKE task starting\n", :buffer => true)

      begin
        validate_parameters

        Maestro.log.info "Inputs: tasks = #{@tasks}"

        shell = Maestro::Util::Shell.new
        shell.create_script(create_command)

        exit_code = shell.run_script_with_delegate(self, :on_output)

        @error = shell.output unless exit_code.success?
      rescue ConfigError => e
        @error = e.message
      rescue Exception => e
        @error = "Error executing Rake Task: #{e.class} #{e}"
        puts e.backtrace.join("\n")
        Maestro.log.warn("Error executing Rake Task: #{e.class} #{e}: " + e.backtrace.join("\n"))
      end

      write_output "\n\nRAKE task complete"
      set_error(@error) if @error
    end

    def on_output(text, is_stderr)
      write_output(text, :buffer => true)
    end

    ###########
    # PRIVATE #
    ###########
    private

    def booleanify(value)
      res = false

      if value
        if value.is_a?(TrueClass) || value.is_a?(FalseClass)
          res = value
        elsif value.is_a?(Fixnum)
          res = value != 0
        elsif value.respond_to?(:to_s)
          value = value.to_s.downcase
            
          res = (value == 't' || value == 'true')
        end
      end
      
      res
    end

    def valid_executable?(executable)
      Maestro::Util::Shell.run_command("#{executable} --version")[0].success?
    end

    def validate_parameters
      errors = []
      @ruby_version = ''
      @rubygems_version = ''

      @rake_executable = get_field('rake_executable', 'rake')
      errors << 'rake not installed' unless valid_executable?(@rake_executable)

      @use_rvm = booleanify(get_field('use_rvm', false))
      @rvm_executable = get_field('rvm_executable', 'rvm')
      errors << 'rvm not installed' if @use_rvm && !valid_executable?(@rvm_executable)

      @ruby_version = get_field('ruby_version', '')
      errors << 'missing ruby_version' if @use_rvm && @ruby_version.empty?

      @rubygems_version = get_field('rubygems_version', '')
      errors << 'missing rubygems_version' if @use_rvm && @rubygems_version.empty?

      @use_bundle = booleanify(get_field('use_bundle', false))
      @bundle_executable = get_field('bundle_executable', 'bundle')
      errors << 'bundle not installed' if @use_bundle && !valid_executable?(@bundle_executable)

      @environment = get_field('environment', '')
      @tasks = get_field('tasks', '')
      @gems = get_field('gems', '')

      @path = get_field('path') || get_field('scm_path')
      errors << 'missing field path' if @path.nil?
      errors << "not found path '#{@path}'" if !@path.nil? && !File.exist?(@path)

      update_ruby_rubygems

      if @use_rvm
        errors << "Requested Ruby version #{@ruby_version} not available" unless @installed_ruby_version && @ruby_version == @installed_ruby_version
        errors << "Requested RubyGems version #{@rubygems_version} not available" unless @installed_rubygems_version && @rubygems_version == @installed_rubygems_version
      end

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
    
      if !(@gems.is_a? Array)
        @gems = nil
        Maestro.log.warn "Invalid Format For gems Field #{@gems} - ignoring"
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

    def create_command
      # TODO consider something in standard ruby such as system({"MYVAR" => "42"}, "echo $MYVAR")
      if @use_bundle
        # ensure we are not overriding a BUNDLE_WITHOUT variable set in the fields
        if @environment.include?("BUNDLE_WITHOUT=")
          bundle_without = ""
        else
          # ENV Var is just one way to get bundle to do without... if you 'bundle config without....' it is stickier and is in
          # the .bundle dir.
          # rake seems to use this more official way of setting... and even though it does clear the .bundle dir on a clean
          # that doesn't help if rake isn't installed!
          bundle_without = "&& #{@bundle_executable} config --delete without && #{Maestro::Util::Shell::ENV_EXPORT_COMMAND} BUNDLE_WITHOUT='' "
        end
        bundle = "#{Maestro::Util::Shell::ENV_EXPORT_COMMAND} BUNDLE_GEMFILE=#{@path}/Gemfile #{bundle_without}&& #{@bundle_executable} install && #{@bundle_executable} exec"
      end
      
      if @gems
        Maestro.log.debug "Install Gems #{@gems.join(', ')}"
        gems_script = ''
        @gems.each do |gem_name|
          gems_script += "gem install #{gem_name} --no-ri --no-rdoc && "
        end
      end
            
      shell_command = <<-Rake
#{Maestro::Util::Shell::ENV_EXPORT_COMMAND} RUBYOPT=
#{@environment.empty? ? "": "#{Maestro::Util::Shell::ENV_EXPORT_COMMAND} #{@environment}" } 
#{@use_rvm ? "#{script_prefix} rvm use #{@ruby_version} && " : ''} cd #{@path} && #{@gems ? gems_script : ''} #{@use_bundle ? bundle : ''} #{@rake_executable} --trace #{@tasks}
Rake

      set_field('command', shell_command)

      Maestro.log.debug("Running #{shell_command}")
      shell_command
    end

  end
end
