# frozen_string_literal: true

# The Budget page (spec §8): the rules themselves, not the money they move.
#
# A singular non-RESTful controller rather than an action on BudgetsController, because the two
# answer different questions: `budgets#index` would be a list of Budget rows, and this page is a
# reading of every rule GROUPED by the pool it fills and ordered by when the money arrives. The
# route is `get "budget"`, named `budget_page` — `budget_path` already belongs to the member
# routes of `resources :budgets`.
class BudgetPageController < ApplicationController
  # Anchored to today rather than to the sidebar's month scrubber, exactly as Home is: every
  # figure here is about the next period's funding, which is a fact about now.
  def show
    @presenter = BudgetPagePresenter.new(user: current_user, today: Date.current)
  end
end
