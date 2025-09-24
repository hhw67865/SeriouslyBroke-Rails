# frozen_string_literal: true

class ApplicationController < ActionController::Base
  include DateContext
  before_action :authenticate_user!
end
