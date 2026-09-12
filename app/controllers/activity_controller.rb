# frozen_string_literal: true

class ActivityController < ApplicationController
  def show
    @presenter = ActivityPresenter.new(user: current_user, page: params[:page])
  end
end
