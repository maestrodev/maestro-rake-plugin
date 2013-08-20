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
    it "should validate fields" do
      workitem['fields']['__error__'].should include('missing field path')
    end

    context "when rake, rvm, bundle not available" do
      let(:fields) {{
        'tasks' => '', 
        'path' => '/tmp',
        'rake_executable' => '/dev/nul',
        'rvm_executable' => '/dev/nul',
        'bundle_executable' => '/dev/nul', 
        'use_rvm' => true,
        'use_bundle' => true
      }}

      it "should detect" do
        workitem['fields']['__error__'].should include("rake not installed")
        workitem['fields']['__error__'].should include("rvm not installed")
        workitem['fields']['__error__'].should include("bundle not installed")
        workitem['fields']['__error__'].should include("missing ruby_version")
      end
    end

    context "when using rvm" do
      let(:fields) {{
        'tasks' => '',
        'path' => '/tmp', 
        'use_rvm' => true,
        'ruby_version' => '99.99.99',
        'rubygems_version' => '99.99.99'
      }}

      it "should validate rvm fields" do
        workitem['fields']['__error__'].should include("Requested Ruby version")
        workitem['fields']['__error__'].should include("Requested RubyGems version")
      end
    end

    context "when using scm path" do
      let(:fields) {{
        'rake_executable' => 'echo 1',
        'scm_path' => '/tmp'
      }}

      it "should validate with only scm path" do
        workitem['__output__'].should include('1')
        workitem['fields']['__error__'].should be_nil
      end
    end

    context "when using gems" do
      let(:fields) {{
        'rake_executable' => 'echo 1',
        'gems' => [],
        'path' => '/tmp'
      }}

      it "should not have errors" do
        workitem['fields']['__error__'].should be_nil
      end
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
#      workitem['fields']['__error__'].should be_nil
#      workitem['fields']['output'].should include("rake, version")
#      workitem['fields']['output'].should_not include("ERROR")
#    end

    context "when running rake with rvm" do
      let(:fields) { super().merge({
        'tasks' => '--version',
        'use_bundle' => false
      }) }

      it 'should run rake with rvm' do
        workitem['fields']['__error__'].should be_nil
        workitem['__output__'].should include("rake, version")
        workitem['__output__'].should_not include("ERROR")
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
#      workitem['fields']['__error__'].should be_nil
#      workitem['fields']['output'].should include("rake, version")
#      workitem['fields']['output'].should include("jruby-1.6.4")
#      workitem['fields']['output'].should_not include("ERROR")
#    end

    context "when running rake with rvm and bundler" do
      let(:fields) { super().merge({
        'tasks' => '--version',
        'environment' => 'CC=/usr/bin/gcc-4.2'
      }) }

      it 'should run rake with rvm and bundler' do
        workitem['fields']['__error__'].should be_nil
        workitem['__output__'].should include("rake, version")
        workitem['__output__'].should_not include("ERROR")
      end
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

      it 'should run rake using scm path w/o rvm & bundler' do
        workitem['fields']['__error__'].should be_nil
        workitem['__output__'].should include("rake, version")
        workitem['__output__'].should_not include("ERROR")
      end
    end
  end

end
