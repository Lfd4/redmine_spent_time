require File.expand_path('../../test_helper', __FILE__)

# Uses Redmine's core fixtures: jsmith (id 2) is Manager (role 1) and dlopper (id 3)
# Developer (role 2) in project 1 (eCookbook).
class SpentTimeControllerTest < ActionController::TestCase
  include SpentTimeTestHelper

  fixtures :projects, :users, :email_addresses, :user_preferences, :members, :member_roles,
           :roles, :enabled_modules, :trackers, :projects_trackers, :issues, :issue_statuses,
           :enumerations, :time_entries, :custom_fields, :custom_values

  def setup
    grant(1, :view_spent_time)
    grant(2, :view_spent_time)
    @request.session[:user_id] = 2
    @activity = TimeEntryActivity.where(:active => true).first
  end

  # A time entry for user, today, in project 1.
  def log_time(user_id, comments, spent_on = Date.today)
    user = User.find(user_id)
    entry = TimeEntry.new
    entry.project = Project.find(1)
    entry.user = user
    entry.author = user if entry.respond_to?(:author=)
    entry.activity = @activity
    entry.hours = 2.5
    entry.spent_on = spent_on
    entry.comments = comments
    entry.save!
    entry
  end

  def today_range
    { :period_type => '2', :from => Date.today.to_s, :to => Date.today.to_s }
  end

  # -- index

  def test_index_shows_own_time_entries
    log_time(2, 'own-entry')
    spent_time_request(:get, :index)
    assert_response :success
    assert_select '#time_entries_report'
    assert_includes response.body, 'own-entry'
  end

  def test_index_requires_login
    @request.session[:user_id] = nil
    spent_time_request(:get, :index)
    assert_response 302
  end

  def test_index_requires_view_spent_time
    Role.all.each { |role| role.remove_permission!(:view_spent_time) }
    spent_time_request(:get, :index)
    assert_response 403
  end

  def test_index_with_view_others_lists_project_members
    grant(1, :view_others_spent_time)
    spent_time_request(:get, :index)
    assert_response :success
    assert_select 'select#user option[value="3"]'
  end

  def test_index_with_view_every_project_lists_active_users
    grant(1, :view_every_project_spent_time)
    spent_time_request(:get, :index)
    assert_response :success
    assert_select 'select#user option[value="3"]'
  end

  # -- report

  def test_report_for_own_user
    log_time(2, 'own-entry')
    spent_time_request(:post, :report, today_range.merge(:user => '2'), true)
    assert_response :success
    assert_includes response.body, 'own-entry'
  end

  def test_report_for_all_time
    log_time(2, 'old-entry', Date.today - 400)
    spent_time_request(:post, :report, { :user => '2', :period_type => '1', :period => 'all' }, true)
    assert_response :success
    assert_includes response.body, 'old-entry'
  end

  def test_report_of_another_user_is_forbidden_without_view_others
    log_time(3, 'their-entry')
    spent_time_request(:post, :report, today_range.merge(:user => '3'), true)
    assert_response 403
    assert_not_includes response.body, 'their-entry'
  end

  def test_report_of_another_user_with_view_others
    grant(1, :view_others_spent_time)
    log_time(3, 'their-entry')
    spent_time_request(:post, :report, today_range.merge(:user => '3'), true)
    assert_response :success
    assert_includes response.body, 'their-entry'
  end

  def test_report_of_unknown_user
    spent_time_request(:post, :report, today_range.merge(:user => '999999'), true)
    assert_response 404
  end

  # -- create_entry

  def new_entry_params(attrs = {})
    { :project_id => '1', :time_entry_spent_on => Date.today.to_s,
      :from => (Date.today - 7).to_s, :to => Date.today.to_s,
      :time_entry => { :hours => '1.5', :activity_id => @activity.id.to_s,
                       :comments => 'logged-here' } }.merge(attrs)
  end

  def test_create_entry
    assert_difference 'TimeEntry.count', 1 do
      spent_time_request(:post, :create_entry, new_entry_params, true)
    end
    assert_response :success
    entry = TimeEntry.order(:id).last
    assert_equal 2, entry.user_id
    assert_equal 1, entry.project_id
    assert_equal 1.5, entry.hours
    assert_equal Date.today, entry.spent_on
    assert_equal 'logged-here', entry.comments
    assert_includes response.body, 'logged-here'
  end

  def test_create_entry_on_an_issue
    issue = Issue.where(:project_id => 1).first
    assert_difference 'TimeEntry.count', 1 do
      spent_time_request(:post, :create_entry, new_entry_params(:issue_id => issue.id.to_s), true)
    end
    assert_equal issue.id, TimeEntry.order(:id).last.issue_id
  end

  def test_create_entry_without_log_time_permission
    revoke(1, :log_time)
    assert_no_difference 'TimeEntry.count' do
      spent_time_request(:post, :create_entry, new_entry_params, true)
    end
  end

  def test_create_entry_with_an_issue_of_another_project
    issue = Issue.where.not(:project_id => 1).first
    assert_no_difference 'TimeEntry.count' do
      spent_time_request(:post, :create_entry, new_entry_params(:issue_id => issue.id.to_s), true)
    end
    assert_includes response.body, 'flash_error'
  end

  def test_create_entry_without_project
    assert_no_difference 'TimeEntry.count' do
      spent_time_request(:post, :create_entry, new_entry_params(:project_id => '-1'), true)
    end
    assert_includes response.body, 'flash_error'
  end

  # -- destroy_entry

  def test_destroy_own_entry
    entry = log_time(2, 'to-delete')
    spent_time_request(:delete, :destroy_entry,
                       { :id => entry.id.to_s, :from => Date.today.to_s, :to => Date.today.to_s }, true)
    assert_response :success
    assert_nil TimeEntry.find_by_id(entry.id)
  end

  def test_destroy_entry_of_another_user_without_permission
    revoke(1, :edit_time_entries)
    entry = log_time(3, 'not-mine')
    spent_time_request(:delete, :destroy_entry,
                       { :id => entry.id.to_s, :from => Date.today.to_s, :to => Date.today.to_s }, true)
    assert_response 403
    assert TimeEntry.find_by_id(entry.id)
  end

  # -- update_project_issues

  def test_update_project_issues
    spent_time_request(:post, :update_project_issues,
                       { :project_id => '1', :from => (Date.today - 7).to_s, :to => Date.today.to_s }, true)
    assert_response :success
    assert_includes response.body, 'issue_id'
  end

  # -- hour format (Redmine's time span format setting)

  def test_hours_follow_the_time_span_format
    log_time(2, 'formatted') # 2.5 hours
    with_settings :timespan_format => 'minutes' do
      spent_time_request(:get, :index)
      assert_select 'tr.time-entry td.issue-hours', :text => '2:30'
    end
    with_settings :timespan_format => 'decimal' do
      spent_time_request(:get, :index)
      assert_select 'tr.time-entry td.issue-hours', :text => '2.50'
    end
  end
end
