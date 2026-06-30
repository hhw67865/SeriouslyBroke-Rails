# frozen_string_literal: true

class ApplicationController < ActionController::Base
  include DateContext

  before_action :authenticate_user!
  prepend_around_action :use_user_timezone

  private

  def use_user_timezone(&)
    Time.use_zone(current_user&.timezone.presence || "UTC", &)
  end
end
