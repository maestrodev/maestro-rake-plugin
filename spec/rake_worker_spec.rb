# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
# 
#  http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.

require 'spec_helper'
require 'rake_worker'

describe MaestroDev::Plugin::RakeWorker do

  let(:ruby_version) { ENV['RUBY_VERSION'] }
  let(:rubygems_version) do
    rg = Maestro::Util::Shell.run_command("rvm #{@ruby_version} do gem --version")
    rg[0].success? ? rg[1].chomp : ''
  end

  before do
    Maestro::MaestroWorker.mock!
    subject.perform(:execute, workitem)
  end

  let(:fields) {{}}
  let(:workitem) {{ 'fields' => fields }}

  describe 'valid_workitem?' do
    its(:error) { should include('missing field path') }

    context "when rvm not available" do
      let(:fields) {{
        'tasks' => '', 
        'path' => '/tmp',
        'rvm_executable' => '/dev/nul',
        'use_rvm' => true,
        'use_bundle' => true
      }}

      its(:error) { should include("rvm not installed") }
    end

    context "when using rvm" do
      let(:fields) {{
        'tasks' => '',
        'path' => '/tmp', 
        'use_rvm' => true,
        'ruby_version' => '99.99.99',
        'rubygems_version' => '99.99.99'
      }}

      its(:error) { should match(/Requested RubyGems version .* not available/) }
    end

    context "when using scm path" do
      let(:fields) {{
        'rake_executable' => 'echo 1',
        'scm_path' => '/tmp'
      }}

      its(:error) { should be_nil }
      its(:output) { should include('1') }
      it { expect(subject.get_field('command')).to match(/^ rvm use default &&  \(gem list rake -i || gem install rake --no-ri --no-rdoc\) && echo 1 --trace --version$/) }
    end

    context "when using gems" do
      let(:fields) {{
        'rake_executable' => 'echo 1',
        'gems' => [],
        'path' => '/tmp'
      }}

      its(:error) { should be_nil }
      it { expect(subject.get_field('command')).to match(/^ rvm use default &&  \(gem list rspec-core -i || gem install rspec-core --no-ri --no-rdoc\) && \(gem list rake -i || gem install rake --no-ri --no-rdoc\) && echo 1 --trace --version$/) }
    end
  end

  describe 'execute' do
    let(:path) { File.join(File.dirname(__FILE__), '..') }
    let(:fields) {{
      'tasks' => '',
      'path' => path,
      'use_rvm' => true,
      'ruby_version' => ruby_version,
      'rubygems_version' => rubygems_version,
      'use_bundle' => true
    }}

    # Problem in that it tries to run bundler outside of rvm
#    it 'should run rake with bundler' do
#      workitem['fields']['tasks'] = '--version'
#      workitem['fields']['use_rvm'] = false
#
#      subject.perform(:execute, workitem)
#
#      puts workitem
#    its(:error) { should be_nil }
#      workitem['fields']['output'].should include("rake, version")
#      workitem['fields']['output'].should_not include("ERROR")
#    end

    context "when running rake with rvm" do
      let(:fields) { super().merge({
        'tasks' => '--version',
        'use_bundle' => false
      }) }

      its(:output) { should include("rake, version", "cd #{path}", "rvm use #{ruby_version}") }
      its(:output) { should_not include("ERROR") }
      its(:error) { should be_nil }
      it { expect(subject.get_field('command')).to match(/^ rvm use #{ruby_version} &&  \(gem list rake -i || gem install rake --no-ri --no-rdoc\) &&  rake --trace --version$/) }

      context "and ruby_version not set" do
        let(:fields) { super().merge({
          'ruby_version' => nil
        }) }

        its(:output) { should include("rake, version") }
        its(:output) { should match(/cd #{Regexp.quote(path)}.*rake/m) }
        its(:output) { should_not include("ERROR") }
        its(:error) { should be_nil }
        it { expect(subject.get_field('command')).to match(/^ rvm use default &&  \(gem list rake -i || gem install rake --no-ri --no-rdoc\) &&  rake --trace --version$/) }
      end
    end

    # This whole thing is running non-mri
#    it 'should run rake with rvm using non mri ruby' do
#      workitem['fields']['tasks'] = '--version'
#      workitem['fields']['environment'] = 'CC=/usr/bin/gcc-4.2'
#      workitem['fields']['ruby_version'] = 'jruby-1.6.4'
#      workitem['fields']['rubygems_version'] = '1.8.6'
#      workitem['fields']['use_bundle'] = false
#         
#         @test_participant.stubs(:update_ruby => [Maestro::Shell::ExitCode.new(0), "all clear"])
#         @test_participant.stubs(:validate_output => 'using /some/path/jruby-1.6.4  rake, version 0.9.2')
#
#      its(:error) { should be_nil }
#      workitem['fields']['output'].should include("rake, version")
#      workitem['fields']['output'].should include("jruby-1.6.4")
#      workitem['fields']['output'].should_not include("ERROR")
#    end

    context "when running rake with rvm and bundler" do
      let(:fields) { super().merge({
        'tasks' => '--version',
        'environment' => 'CC=/usr/bin/gcc-4.2'
      }) }

      its(:output) { should include("rake, version", "cd #{path}", "rvm use #{ruby_version}") }
      its(:output) { should_not include("ERROR") }
      its(:error) { should be_nil }
      it { expect(subject.get_field('command')).to match(/^ rvm use #{ruby_version} &&  \(gem list bundler -i || gem install bundler --no-ri --no-rdoc\) &&   export BUNDLE_GEMFILE=.*\/Gemfile && bundle config --delete without && export BUNDLE_WITHOUT='' && bundle install && bundle exec  rake --trace --version$/) }
    end

    context "when running rake with rvm and a specific version of bundler" do
      let(:fields) { super().merge({
        'tasks' => '--version',
        'environment' => 'CC=/usr/bin/gcc-4.2',
        'bundler_version' => '1.6.5'
      }) }

      its(:output) { should include("rake, version", "cd #{path}", "rvm use #{ruby_version}") }
      its(:output) { should_not include("ERROR") }
      its(:error) { should be_nil }
      it { expect(subject.get_field('command')).to match(/^ rvm use #{ruby_version} &&  \(gem list bundler -v 1.6.5 -i || gem install bundler -v 1.6.5 --no-ri --no-rdoc\) && export BUNDLE_GEMFILE=.*\/Gemfile && bundle _1.6.5_ config --delete without && export BUNDLE_WITHOUT='' && bundle _1.6.5_ install && bundle _1.6.5_ exec  rake --trace --version$/) }
    end

    context "when running rake using scm path w/o rvm & bundler" do
      let(:fields) { super().merge({
        'tasks' => '--version',
        'path' => nil,
        'scm_path' => path,
        'use_rvm' => false,
        'environment' => 'CC=/usr/bin/gcc-4.2',
        'use_bundle' => false,
        'rake_executable' => 'echo "fake rake, version"'
      }) }

      its(:error) { should be_nil }
      its(:output) { should include("rake, version") }
      its(:output) { should_not include("ERROR") }
      it { expect(subject.get_field('command')).to match(/^ rvm use #{ruby_version} &&  \(gem list rake -i || gem install rake --no-ri --no-rdoc\) &&  rake --trace --version$/) }
    end
  end

end
