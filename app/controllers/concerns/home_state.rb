# frozen_string_literal: true

# The state the home page renders with, for the controllers that re-render it after a refusal.
module HomeState
  extend ActiveSupport::Concern

  private

  def assign_home_state(new_account: nil, new_account_balance: nil)
    @presenter = HomePresenter.new(user: current_user, today: current_user.today)
    @new_account = new_account || current_user.accounts.new
    @new_account_balance = new_account_balance
  end
end
