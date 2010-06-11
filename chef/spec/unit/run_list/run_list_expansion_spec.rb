#
# Author:: Daniel DeLeo (<dan@opscode.com>)
# Copyright:: Copyright (c) 2010 Opscode, Inc.
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

require File.expand_path(File.dirname(__FILE__) + '/../../spec_helper')

describe Chef::RunList::RunListExpansion do
  before do
    @run_list = Chef::RunList.new
    @run_list << 'recipe[lobster]' << 'role[rage]' << 'recipe[fist]'
    @expansion = Chef::RunList::RunListExpansion.new(@run_list.run_list_items)
  end
  
  describe "before expanding the run list" do
    it "has an array of run list items" do
      @expansion.run_list_items.should == @run_list.run_list_items
    end
  
    it "has default_attrs" do
      @expansion.default_attrs.should == Mash.new
    end
  
    it "has override attrs" do
      @expansion.override_attrs.should == Mash.new
    end
  
    it "it has an empty list of recipes" do
      @expansion.should have(0).recipes
    end
    
    it "has not applied its roles" do
      @expansion.applied_role?('rage').should be_false
    end
  end
  
  describe "after applying a role" do
    before do
      @expansion.applied_role('rage')
    end
    
    it "tracks the applied role" do
      @expansion.applied_role?('rage').should be_true
    end
    
    it "does not inflate the role again" do
      @expansion.inflate_role('rage').should be_false
    end
  end
  
  describe "after expanding a run list" do
    before do
      @inflated_role = Chef::Role.new
      @inflated_role.run_list('recipe[crabrevenge]')
      @inflated_role.default_attributes({'foo' => 'bar'})
      @inflated_role.override_attributes({'baz' => 'qux'})
      @expansion.stub!(:fetch_role).and_return(@inflated_role)
      @expansion.expand
    end
    
    it "has the ordered list of recipes" do
      @expansion.recipes.should == ['lobster', 'crabrevenge', 'fist']
    end
    
    it "has the merged attributes from the roles" do
      @expansion.default_attrs.should == {'foo' => 'bar'}
      @expansion.override_attrs.should == {'baz' => 'qux'}
    end
  end
end
