# Scrumbler - Add scrum functionality to any Redmine installation
# Copyright (C) 2011 256Mb Team
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

class ScrumblerSprint < ActiveRecord::Base
  unloadable
  
  OPENED = "opened"
  PLANNING = "planning"
  CLOSED = "closed"
  
  STATUSES = [OPENED, PLANNING, CLOSED]
  validates_inclusion_of :status, :in => ScrumblerSprint::STATUSES
    
  default_scope :joins => [:version], :select => "#{ScrumblerSprint.table_name}.*, name"
  
  named_scope :opened, :conditions => {:status => OPENED}
  
  named_scope :planning, :conditions => {:status => PLANNING}
  
  belongs_to :project
  validates_presence_of :project
  
  belongs_to :version
  validates_presence_of :version

  validates_uniqueness_of :status, :scope => :project_id, :if => lambda {|sprint| sprint.status == OPENED}, :message => :only_one_opened 
  
  delegate :scrumbler_project_setting, :to => :project
  
  serialize :settings, HashWithIndifferentAccess
  
  validate :scrumbler_project_setting_validation
  validate :closing_validation
  validate :remove_tracker_validation
  validate :start_end_date_validation
  validate :opening_validation
  
  def issues
    Issue.find :all, 
               :include => [:assigned_to, :status, :priority], 
               :conditions => {
                 :tracker_id => self.trackers.keys,
                 :status_id => self.issue_statuses.keys,
                 :fixed_version_id => self.version_id
                }
  end
  
  def points_total
    CustomValue.find(:all, :conditions => {
      :custom_field_id => ScrumblerIssueCustomField.points.id,
      :customized_type => 'Issue',
      :customized_id => (self.issues.map(&:id) << 0)
    }).inject(0.0) {|t,c| t+=c.value.to_f}
  end
  
  
  def after_initialize
    if self.new_record?
      self.status ||= ScrumblerSprint::PLANNING
    end
    self.settings ||= HashWithIndifferentAccess.new
  end
  
  def trackers
    self.settings[:trackers] || scrumbler_project_setting.try(:trackers)
  end 
  
  def issue_statuses
    self.settings[:issue_statuses] || scrumbler_project_setting.try(:issue_statuses)
  end
  
  def end_date=(date)
    version.effective_date = date
    version.save
  end
  
  def end_date
    version.effective_date
  end
  
  def statistics_available?
    status != ScrumblerSprint::PLANNING && start_date && end_date
  end
  
  private
  
  def scrumbler_project_setting_validation
    if !project || !scrumbler_project_setting
      errors.add_to_base(:sprint_without_project) 
    end
  end
  
  def closing_validation
    if Issue.open.exists?(:id => self.issues.map(&:id)) && self.status == CLOSED
      errors.add_to_base(:closing_sprint_with_opened_issues) 
    end
  end
  
  def opening_validation
    if self.status == OPENED && self.issues.empty?
         errors.add_to_base(:cant_open_sprint_without_issues)
    end
  end
  
  def remove_tracker_validation
    if Issue.exists?(["tracker_id not in (?) and fixed_version_id = ?", self.trackers.keys, self.version_id])
         errors.add_to_base(:trackers_with_issues_in_sprint_cant_be_removed) 
    end
  end
  
  def start_end_date_validation
    if start_date && end_date && start_date > end_date
         errors.add_to_base(:start_date_is_greater_than_end_date)
    end
  end
  
end
