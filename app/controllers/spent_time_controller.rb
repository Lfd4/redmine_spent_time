class SpentTimeController < ApplicationController

  helper :timelog
  include TimelogHelper
  helper :spent_time
  include SpentTimeHelper
  helper :custom_fields
  include CustomFieldsHelper

  before_action :require_login
  before_action :authorize_spent_time

  # Show the initial form.
  # * If user has permissions to see spent time for every project
  # the users combobox is filled with all the users.
  # * If user has permissions to see other members' spent times of the projects he works in,
  # the users combobox is filled with their co-workers
  # * If the user only has permissions to see his own report, the users' combobox is filled with the user himself.
  def index
    @user = User.current
    @users = []
    if authorized_for?(:view_every_project_spent_time)
      @users = User.active.order(:firstname).to_a
    elsif authorized_for?(:view_others_spent_time)
      User.current.projects.each { |project| @users.concat(project.users) }
      @users = @users.uniq.sort_by { |u| [u.firstname.to_s, u.lastname.to_s] }
    else
      @users = [@user]
    end
    params[:period] ||= '7_days'
    make_time_entry_report(nil, nil, User.current)
    @assigned_issues = []
    @same_user = true
    @time_entry = TimeEntry.new
  end

  # Show the report of spent time between two dates for an user
  def report
    @user = User.current
    report_user = User.find_by_id(params[:user])
    return render_404 unless report_user

    projects = nil
    if authorized_for?(:view_every_project_spent_time)
      # all project, which are not archived
      projects = Project.where('status!=9')
    elsif authorized_for?(:view_others_spent_time)
      projects = User.current.projects
    elsif report_user != @user
      return render_403
    end
    make_time_entry_report(params[:from], params[:to], report_user, projects)
    @same_user = (@user == report_user)
    respond_to do |format|
      format.js
    end
  end

  # Delete a time entry
  def destroy_entry
    @time_entry = TimeEntry.find_by_id(params[:id])
    return render_404 unless @time_entry
    return render_403 unless @time_entry.editable_by?(User.current)
    @time_entry.destroy

    @user = User.current
    make_time_entry_report(params[:from], params[:to], @user)
    respond_to do |format|
      format.js
    end
  end

  # Create a new time entry
  def create_entry
    @user = User.current
    raise t('project_is_mandatory_error') if params[:project_id].to_i < 0

    begin
      @time_entry_date = params[:time_entry_spent_on].to_s.to_date
    rescue
      raise t('invalid_date_error')
    end
    raise t('invalid_date_error') unless @time_entry_date

    time_entry_params = params[:time_entry] || {}
    time_entry_params[:spent_on] = @time_entry_date
    @from = params[:from].to_s.to_date
    @to = params[:to].to_s.to_date

    @project = Project.find_by_id(params[:project_id])
    raise t('cannot_find_project_error', :project_id => params[:project_id]) unless @project
    raise t('not_allowed_error', :project => @project) unless @user.allowed_to?(:log_time, @project)

    @time_entry = TimeEntry.new
    @time_entry.project = @project
    @time_entry.user = @user
    @time_entry.author = @user if @time_entry.respond_to?(:author=)
    @time_entry.safe_attributes = time_entry_params

    issue_id = params[:issue_id].to_i
    if issue_id > 0
      @issue = Issue.find_by_id(issue_id)
      raise t('issue_not_found_error', :issue_id => issue_id) unless @issue
      unless @project.id == @issue.project_id
        raise t('issue_not_in_project_error', :issue => @issue.id, :project => @project)
      end
      @time_entry.issue = @issue
    end

    @time_entry.save!
    flash[:notice] = l('time_entry_added_notice')
    if @time_entry_date > @to
      @to = @time_entry_date
    elsif @time_entry_date < @from
      @from = @time_entry_date
    end
    make_time_entry_report(@from, @to, @user)
    respond_to do |format|
      format.js
    end
  rescue StandardError => ex
    flash[:error] = ex.message
    respond_to do |format|
      format.js { render 'spent_time/create_entry_error' }
    end
  end

  # Update the project's issues when another project is selected
  def update_project_issues
    @to = params[:to].to_s.to_date
    @from = params[:from].to_s.to_date
    project = Project.find_by_id(params[:project_id])
    @time_entry = TimeEntry.new
    @time_entry.project = project
    find_assigned_issues_by_project(project)
    respond_to do |format|
      format.js
    end
  end

  private

  def authorize_spent_time
    render_403 unless authorized_for?(:view_spent_time)
  end
end
