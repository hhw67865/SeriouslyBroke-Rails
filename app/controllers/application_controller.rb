# frozen_string_literal: true

class ApplicationController < ActionController::Base
  around_action :use_user_timezone

  include DateContext

  before_action :authenticate_user!

  private

  def use_user_timezone(&)
    Time.use_zone(current_user&.timezone.presence || "UTC", &)
  end
end
