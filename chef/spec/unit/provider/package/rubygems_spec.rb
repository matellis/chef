#
# Author:: David Balatero (dbalatero@gmail.com)
#
# Copyright:: Copyright (c) 2009 David Balatero
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
require 'pp'

require File.expand_path(File.join(File.dirname(__FILE__), "..", "..", "..", "spec_helper"))
require 'ostruct'

class String
  undef_method :version
end

class NilClass
  undef_method :version
end


class Chef::Resource

  def to_text
    skip = [:@allowed_actions, :@resource_name, :@source_line]
    ivars = instance_variables.map { |ivar| ivar.to_sym }
    text = "# Declared in #{@source_line}\n"
    text << convert_to_snake_case(self.class.name, 'Chef::Resource') + "(#{name}) do\n"
    ivars.each do |ivar|
      next if skip.include?(ivar)
      if (value = instance_variable_get(ivar)) && !(value.respond_to?(:empty?) && value.empty?)
        text << "  #{ivar.to_s.sub(/^@/,'')}(#{value.inspect})\n"
      end
    end
    text << "end\n"
  end
end

describe Chef::Provider::Package::Rubygems::CurrentGemEnvironment do
  before do
    @gem_env = Chef::Provider::Package::Rubygems::CurrentGemEnvironment.new
  end

  it "determines the gem paths from the in memory rubygems" do
    @gem_env.gem_paths.should == Gem.path
  end

  it "determines the installed versions of gems from Gem.source_index" do
    gems = [Gem::Specification.new('rspec', Gem::Version.new('1.2.9')), Gem::Specification.new('rspec', Gem::Version.new('1.3.0'))]
    Gem.source_index.should_receive(:search).with(Gem::Dependency.new('rspec', nil)).and_return(gems)
    @gem_env.installed_versions(Gem::Dependency.new('rspec', nil)).should == gems
  end

  it "determines the installed versions of gems from the source index (part2: the unmockening)" do
    expected = ['rspec', Gem::Version.new(Spec::VERSION::STRING)]
    actual = @gem_env.installed_versions(Gem::Dependency.new('rspec', nil)).map { |spec| [spec.name, spec.version] }
    actual.should include(expected)
  end

  it "yields to a block with an alternate source list set" do
    sources_in_block = nil
    normal_sources = Gem.sources
    begin
      @gem_env.with_gem_sources("http://gems.example.org") do
        sources_in_block = Gem.sources
        raise RuntimeError, "sources should be reset even in case of an error"
      end
    rescue RuntimeError
    end
    sources_in_block.should == %w{http://gems.example.org}
    Gem.sources.should == normal_sources
  end

  it "it doesnt alter the gem sources if none are set" do
    sources_in_block = nil
    normal_sources = Gem.sources
    begin
      @gem_env.with_gem_sources(nil) do
        sources_in_block = Gem.sources
        raise RuntimeError, "sources should be reset even in case of an error"
      end
    rescue RuntimeError
    end
    sources_in_block.should == normal_sources
    Gem.sources.should == normal_sources
  end

  it "finds a matching gem candidate version" do
    dep = Gem::Dependency.new('rspec')
    dep_installer = Gem::DependencyInstaller.new
    @gem_env.stub!(:dependency_installer).and_return(dep_installer)
    latest = [[Gem::Specification.new("rspec", Gem::Version.new("1.3.0")), "http://rubygems.org/"]]
    dep_installer.should_receive(:find_gems_with_sources).with(dep).and_return(latest)
    @gem_env.candidate_version_from_remote(Gem::Dependency.new('rspec')).should == Gem::Version.new('1.3.0')
  end

  it "gives the candidate version as nil if none is found" do
    dep = Gem::Dependency.new('rspec')
    latest = []
    dep_installer = Gem::DependencyInstaller.new
    @gem_env.stub!(:dependency_installer).and_return(dep_installer)
    dep_installer.should_receive(:find_gems_with_sources).with(dep).and_return(latest)
    @gem_env.candidate_version_from_remote(Gem::Dependency.new('rspec')).should be_nil
  end

  it "finds a matching candidate version from a .gem file when the path to the gem is supplied" do
    location = CHEF_SPEC_DATA + '/gems/chef-integration-test-0.1.0.gem'
    @gem_env.candidate_version_from_file(Gem::Dependency.new('chef-integration-test'), location).should == Gem::Version.new('0.1.0')
    @gem_env.candidate_version_from_file(Gem::Dependency.new('chef-integration-test', '>= 0.2.0'), location).should be_nil
  end

  it "finds a matching gem from a specific gemserver when explicit sources are given" do
    dep = Gem::Dependency.new('rspec')
    latest = [[Gem::Specification.new("rspec", Gem::Version.new("1.3.0")), "http://rubygems.org/"]]

    @gem_env.should_receive(:with_gem_sources).with('http://gems.example.com').and_yield
    dep_installer = Gem::DependencyInstaller.new
    @gem_env.stub!(:dependency_installer).and_return(dep_installer)
    dep_installer.should_receive(:find_gems_with_sources).with(dep).and_return(latest)
    @gem_env.candidate_version_from_remote(Gem::Dependency.new('rspec'), 'http://gems.example.com').should == Gem::Version.new('1.3.0')
  end

  it "installs a gem with a hash of options for the dependency installer" do
    dep_installer = Gem::DependencyInstaller.new
    @gem_env.should_receive(:dependency_installer).with(:install_dir => '/foo/bar').and_return(dep_installer)
    @gem_env.should_receive(:with_gem_sources).with('http://gems.example.com').and_yield
    dep_installer.should_receive(:install).with(Gem::Dependency.new('rspec'))
    @gem_env.install(Gem::Dependency.new('rspec'), :install_dir => '/foo/bar', :sources => ['http://gems.example.com'])
  end

end

describe Chef::Provider::Package::Rubygems::AlternateGemEnvironment do
  before do
    @gem_env = Chef::Provider::Package::Rubygems::AlternateGemEnvironment.new('/usr/weird/bin/gem')
  end

  it "determines the gem paths from shelling out to gem env" do
    gem_env_output = ['/path/to/gems', '/another/path/to/gems'].join(File::PATH_SEPARATOR)
    shell_out_result = OpenStruct.new(:stdout => gem_env_output)
    @gem_env.should_receive(:shell_out!).with('/usr/weird/bin/gem env gempath').and_return(shell_out_result)
    @gem_env.gem_paths.should == ['/path/to/gems', '/another/path/to/gems']
  end

  it "builds the gems source index from the gem paths" do
    Gem::SourceIndex.should_receive(:from_gems_in).with('/path/to/gems/specifications', '/another/path/to/gems/specifications')
    @gem_env.stub!(:gem_paths).and_return(['/path/to/gems', '/another/path/to/gems'])
    @gem_env.gem_source_index
  end

  it "determines the installed versions of gems from the source index" do
    gems = [Gem::Specification.new('rspec', Gem::Version.new('1.2.9')), Gem::Specification.new('rspec', Gem::Version.new('1.3.0'))]
    @gem_env.stub!(:gem_source_index).and_return(Gem.source_index)
    @gem_env.gem_source_index.should_receive(:search).with(Gem::Dependency.new('rspec', nil)).and_return(gems)
    @gem_env.installed_versions(Gem::Dependency.new('rspec', nil)).should == gems
  end

  it "determines the installed versions of gems from the source index (part2: the unmockening)" do
    path_to_gem = `which gem`.strip
    pending("cant find your gem executable") if path_to_gem.empty?
    gem_env = Chef::Provider::Package::Rubygems::AlternateGemEnvironment.new(path_to_gem)
    expected = ['rspec', Gem::Version.new(Spec::VERSION::STRING)]
    actual = gem_env.installed_versions(Gem::Dependency.new('rspec', nil)).map { |s| [s.name, s.version] }
    actual.should include(expected)
  end

  it "detects when the target gem environment is the jruby platform" do
    gem_env_out=<<-JRUBY_GEM_ENV
RubyGems Environment:
  - RUBYGEMS VERSION: 1.3.6
  - RUBY VERSION: 1.8.7 (2010-05-12 patchlevel 249) [java]
  - INSTALLATION DIRECTORY: /Users/you/.rvm/gems/jruby-1.5.0
  - RUBY EXECUTABLE: /Users/you/.rvm/rubies/jruby-1.5.0/bin/jruby
  - EXECUTABLE DIRECTORY: /Users/you/.rvm/gems/jruby-1.5.0/bin
  - RUBYGEMS PLATFORMS:
    - ruby
    - universal-java-1.6
  - GEM PATHS:
     - /Users/you/.rvm/gems/jruby-1.5.0
     - /Users/you/.rvm/gems/jruby-1.5.0@global
  - GEM CONFIGURATION:
     - :update_sources => true
     - :verbose => true
     - :benchmark => false
     - :backtrace => false
     - :bulk_threshold => 1000
     - "install" => "--env-shebang"
     - "update" => "--env-shebang"
     - "gem" => "--no-rdoc --no-ri"
     - :sources => ["http://rubygems.org/", "http://gems.github.com/"]
  - REMOTE SOURCES:
     - http://rubygems.org/
     - http://gems.github.com/
JRUBY_GEM_ENV
    @gem_env.should_receive(:shell_out!).with('/usr/weird/bin/gem env').and_return(mock('jruby_gem_env', :stdout => gem_env_out))
    @gem_env.gem_platforms.should == ['ruby', Gem::Platform.new('universal-java-1.6')]
  end

  it "uses the current gem platforms when the target env is not jruby" do
    gem_env_out=<<-RBX_GEM_ENV
RubyGems Environment:
  - RUBYGEMS VERSION: 1.3.6
  - RUBY VERSION: 1.8.7 (2010-05-14 patchlevel 174) [x86_64-apple-darwin10.3.0]
  - INSTALLATION DIRECTORY: /Users/ddeleo/.rvm/gems/rbx-1.0.0-20100514
  - RUBYGEMS PREFIX: /Users/ddeleo/.rvm/rubies/rbx-1.0.0-20100514
  - RUBY EXECUTABLE: /Users/ddeleo/.rvm/rubies/rbx-1.0.0-20100514/bin/rbx
  - EXECUTABLE DIRECTORY: /Users/ddeleo/.rvm/gems/rbx-1.0.0-20100514/bin
  - RUBYGEMS PLATFORMS:
    - ruby
    - x86_64-darwin-10
    - x86_64-rubinius-1.0
  - GEM PATHS:
     - /Users/ddeleo/.rvm/gems/rbx-1.0.0-20100514
     - /Users/ddeleo/.rvm/gems/rbx-1.0.0-20100514@global
  - GEM CONFIGURATION:
     - :update_sources => true
     - :verbose => true
     - :benchmark => false
     - :backtrace => false
     - :bulk_threshold => 1000
     - :sources => ["http://rubygems.org/", "http://gems.github.com/"]
     - "gem" => "--no-rdoc --no-ri"
  - REMOTE SOURCES:
     - http://rubygems.org/
     - http://gems.github.com/
RBX_GEM_ENV
    @gem_env.should_receive(:shell_out!).with('/usr/weird/bin/gem env').and_return(mock('rbx_gem_env', :stdout => gem_env_out))
    @gem_env.gem_platforms.should == Gem.platforms
  end

  it "yields to a block while masquerading as a different gems platform" do
    original_platforms = Gem.platforms
    platforms_in_block = nil
    begin
      @gem_env.with_gem_platforms(['ruby', Gem::Platform.new('sparc64-java-1.7')]) do
        platforms_in_block = Gem.platforms
        raise "gem platforms should get set to the correct value even when an error occurs"
      end
    rescue RuntimeError
    end
    platforms_in_block.should == ['ruby', Gem::Platform.new('sparc64-java-1.7')]
    Gem.platforms.should == original_platforms
  end

end

describe Chef::Provider::Package::Rubygems do
  before(:each) do
    @node = Chef::Node.new
    @new_resource = Chef::Resource::GemPackage.new("rspec")
    @spec_version = @new_resource.version Spec::VERSION::STRING
    @run_context = Chef::RunContext.new(@node, {})

    @provider = Chef::Provider::Package::Rubygems.new(@new_resource, @run_context)
  end

  it "uses the CurrentGemEnvironment implementation when no gem_binary_path is provided" do
    @provider.gem_env.should be_a_kind_of(Chef::Provider::Package::Rubygems::CurrentGemEnvironment)
  end

  it "uses the AlternateGemEnvironment implementation when a gem_binary_path is provided" do
    @new_resource.gem_binary('/usr/weird/bin/gem')
    provider = Chef::Provider::Package::Rubygems.new(@new_resource, @run_context)
    provider.gem_env.gem_binary_location.should == '/usr/weird/bin/gem'
  end

  it "converts the new resource into a gem dependency" do
    @provider.gem_dependency.should == Gem::Dependency.new('rspec', @spec_version)
    @new_resource.version('~> 1.2.0')
    @provider.gem_dependency.should == Gem::Dependency.new('rspec', '~> 1.2.0')
  end

  describe "when determining the currently installed version" do

    it "sets the current version to the version specified by the new resource if that version is installed" do
      @provider.load_current_resource
      @provider.current_resource.version.should == @spec_version
    end

    it "sets the current version to the highest installed version if the requested version is not installed" do
      @new_resource.version('9000.0.2')
      @provider.load_current_resource
      @provider.current_resource.version.should == @spec_version
    end

  end

  describe "when determining the candidate version to install" do

    it "does not query for available versions when the current version is the target version" do
      @provider.current_resource = @new_resource.dup
      @provider.candidate_version.should be_nil
    end

    it "determines the candidate version by querying the remote gem servers" do
      @new_resource.source('http://mygems.example.com')
      version = Gem::Version.new(@spec_version)
      @provider.gem_env.should_receive(:candidate_version_from_remote).
                        with(Gem::Dependency.new('rspec', @spec_version), "http://mygems.example.com", "http://rubygems.org").
                        and_return(version)
      @provider.candidate_version.should == @spec_version
    end

    it "parses the gem's specification if the requested source is a file" do
      @new_resource.package_name('chef-integration-test')
      @new_resource.version('>= 0')
      @new_resource.source(CHEF_SPEC_DATA + '/gems/chef-integration-test-0.1.0.gem')
      @provider.candidate_version.should == '0.1.0'
    end

  end

  describe "when installing a gem" do
    describe "in the current gem environment" do
      before do
        @current_resource = Chef::Resource::GemPackage.new('rspec')
        @provider.current_resource = @current_resource
      end

      it "installs the gem via the gems api when no explicit options are used" do
        pending
      end

      it "installs the gem from file via the gems api when no explicit options are used" do
        @new_resource.source(CHEF_SPEC_DATA + '/gems/chef-integration-test-0.1.0.gem')
        @provider.current_resource
        @provider.gem_env.should_receive(:install).with(CHEF_SPEC_DATA + '/gems/chef-integration-test-0.1.0.gem')
        @provider.action_install
      end

      it "installs the gem by shelling out when options are provided as a String" do
        pending
      end

      it "installs the gem via the gems api when options are given as a Hash" do
        pending
      end
    end

    describe "in an alternate gem environment" do
      it "installs the gem by shelling out to gem install" do
        pending
      end
    end

  end

  # describe "when installing a gem" do
  #   it "should run gem install with the package name and version" do
  #     @provider.should_receive(:run_command).with(
  #       :command => "gem install rspec -q --no-rdoc --no-ri -v \"1.2.2\"",
  #       :environment => {"LC_ALL" => nil})
  #     @provider.install_package("rspec", "1.2.2")
  #   end
  #
  #   it "installs gems with arbitrary options set by resource's options" do
  #     @new_resource.options "-i /arbitrary/install/dir"
  #     @provider.should_receive(:run_command_with_systems_locale).
  #       with(:command => "gem install rspec -q --no-rdoc --no-ri -v \"1.2.2\" -i /arbitrary/install/dir")
  #     @provider.install_package("rspec", "1.2.2")
  #   end
  # end
end
