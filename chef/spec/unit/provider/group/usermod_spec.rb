#
# Author:: AJ Christensen (<aj@opscode.com>)
# Copyright:: Copyright (c) 2008 OpsCode, Inc.
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

require File.expand_path(File.join(File.dirname(__FILE__), "..", "..", "..", "spec_helper"))

describe Chef::Provider::Group::Usermod, "modify_group_members" do
  before do
    @node = mock("Chef::Node", :null_object => true)
    @new_resource = mock("Chef::Resource::Group",
      :null_object => true,
      :group_name => "aj",
      :members => [ "all", "your", "base" ],
      :append => false
    )
    @new_resource.stub!(:to_s).and_return("group[aj]")
    @provider = Chef::Provider::Group::Usermod.new(@node, @new_resource)
    @provider.stub!(:node).and_return(@node)
    @provider.stub!(:run_command).and_return(true)
  end
  
  describe "with an empty members array" do
    before do
      @new_resource.stub!(:members).and_return([])
    end
    
    it "should log an appropriate message" do
      Chef::Log.should_receive(:debug).with("group[aj]: not changing group members, the group has no members")
      @provider.modify_group_members
    end
  end
  
  describe "with supplied members" do
    platforms = {
      "openbsd" => "-G",
      "netbsd" => "-G",
      "solaris" => "-a -G"
    }

    before do
      @new_resource.stub!(:members).and_return(["all", "your", "base"])
    end

    it "should raise an error when setting the entire group directly" do
      lambda { @provider.modify_group_members }.should raise_error(Chef::Exceptions::Group, "setting group members directly is not supported by #{@provider.to_s}")
    end
    
    platforms.each do |platform, flags|
      it "should usermod each user when the append option is set on #{platform}" do
        @node.stub!(:[]).with(:platform).and_return(platform)
        @new_resource.stub!(:append).and_return(true)
        @provider.should_receive(:run_command).with({:command => "usermod #{flags} aj all"})
        @provider.should_receive(:run_command).with({:command => "usermod #{flags} aj your"})
        @provider.should_receive(:run_command).with({:command => "usermod #{flags} aj base"})
        @provider.modify_group_members
      end
    end
  end
end

describe Chef::Provider::Group::Usermod, "load_current_resource" do
  before do
    @node = mock("Chef::Node", :null_object => true)
    @new_resource = mock("Chef::Resource::Group", :null_object => true, :group_name => "aj")
    @provider = Chef::Provider::Group::Usermod.new(@node, @new_resource)
    File.stub!(:exists?).and_return(false)
  end

  it "should raise an error if the required binary /usr/sbin/groupadd doesn't exist" do
    File.should_receive(:exists?).with("/usr/sbin/groupadd").and_return(false)
    lambda { @provider.load_current_resource }.should raise_error(Chef::Exceptions::Group)
  end
  it "should raise an error if the required binary /usr/sbin/groupmod doesn't exist" do
    File.should_receive(:exists?).with("/usr/sbin/groupadd").and_return(true)
    File.should_receive(:exists?).with("/usr/sbin/groupmod").and_return(false)
    lambda { @provider.load_current_resource }.should raise_error(Chef::Exceptions::Group)
  end
  it "should raise an error if the required binary /usr/sbin/groupdel doesn't exist" do
    File.should_receive(:exists?).with("/usr/sbin/groupadd").and_return(true)
    File.should_receive(:exists?).with("/usr/sbin/groupmod").and_return(true)
    File.should_receive(:exists?).with("/usr/sbin/groupdel").and_return(false)
    lambda { @provider.load_current_resource }.should raise_error(Chef::Exceptions::Group)
  end
  it "should raise an error if the required binary /usr/sbin/usermod doesn't exist" do
    File.should_receive(:exists?).with("/usr/sbin/groupadd").and_return(true)
    File.should_receive(:exists?).with("/usr/sbin/groupmod").and_return(true)
    File.should_receive(:exists?).with("/usr/sbin/groupdel").and_return(true)
    File.should_receive(:exists?).with("/usr/sbin/usermod").and_return(false)
    lambda { @provider.load_current_resource }.should raise_error(Chef::Exceptions::Group)
  end
  
  it "shouldn't raise an error if the required binaries exist" do
    File.stub!(:exists?).and_return(true)
    lambda { @provider.load_current_resource }.should_not raise_error(Chef::Exceptions::Group)
  end
end
