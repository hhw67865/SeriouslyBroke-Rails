# frozen_string_literal: true

class HomeController < ApplicationController
  include HomeState

  def index
    assign_home_state
  end
end
