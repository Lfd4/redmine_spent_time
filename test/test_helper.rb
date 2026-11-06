# Load the normal Rails helper
require File.expand_path(File.dirname(__FILE__) + '/../../../test/test_helper')

module SpentTimeTestHelper
  # Functional requests that work on Rails 4.2 (Redmine 3.x) and Rails 5+ (Redmine 4+):
  # Rails 5 takes params: / xhr: keywords, Rails 4.2 a plain params hash and #xhr.
  def spent_time_request(method, action, params = {}, xhr = false)
    if Rails::VERSION::MAJOR >= 5
      send(method, action, :params => params, :xhr => xhr)
    elsif xhr
      self.xhr(method, action, params)
    else
      send(method, action, params)
    end
  end

  def grant(role_id, *permissions)
    role = Role.find(role_id)
    permissions.each { |p| role.add_permission!(p) }
  end

  def revoke(role_id, *permissions)
    role = Role.find(role_id)
    permissions.each { |p| role.remove_permission!(p) }
  end
end
