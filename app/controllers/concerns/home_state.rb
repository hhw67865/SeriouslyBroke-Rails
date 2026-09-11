# frozen_string_literal: true

# The state the home page renders with, for the controllers that re-render it after a refusal.
module HomeState
  extend ActiveSupport::Concern

  private

  def assign_home_state
    @presenter = HomePresenter.new(user: current_user, today: current_user.today)
  end

  def refuse_on_home(message)
    flash.now[:alert] = message
    assign_home_state
    render "home/index", status: :unprocessable_content
  end
end
