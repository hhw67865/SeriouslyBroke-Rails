# frozen_string_literal: true

class HomeController < ApplicationController
  def index
    @presenter = HomePresenter.new(user: current_user, today: Date.current)
  end
end
