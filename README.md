maestro-rake-plugin
====================

A Maestro Plugin that provides integration with Rake (direct, via rvm, via bundler)

Task Parameters
---------------

* "Use RVM"

  Whether to use RVM to run rake.  If specified, both 'Ruby Version' and
  'RubyGems Version' are required.

* "Ruby Version" (required if 'Use RVM' is true)

  Default: ""
  
  The Version string to pass RVM (as in 'rvm use $RUBY_VERSION')

* "RubyGems Version" (required if 'Use RVM' is true)

  Default: ""

* "Use Bundle"

  Default: ""

  Whether to use bundler to run rake.
  Can be used in conjunction with 'Use RVM' if desired.

* "Path"

  Default: ""

  A valid path to a directory containing the Rakefile to execute

* "Environment"

  Default: ""

  Environment string to pass to command shell immediately prior to running Rake

* "Tasks"

  Rake tasks to run.  Leave blank to have default task(s) run.

* "Gems"

  Default: [] (empty)

  A list of ruby gems that are required to be installed prior to running Rake
