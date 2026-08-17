# frozen_string_literal: true

# THE SACRIFICE VIEW (spec §9): the screen the structural check's button opens, and the only
# answer this app has to a budget that does not fit an income.
#
# A singular non-RESTful GET, like the Budget page beside it. There is no Sacrifice to show —
# nothing here is a record and nothing here is written (plan decision 3) — so `resources` would
# be a lie about what the route does. `sacrifices#show` rather than a `budget_page#sacrifice`
# action because it is its own screen with its own presenter, and BudgetPageController already
# carries the two writers for the declaration and the fill order.
class SacrificesController < ApplicationController
  # ANCHORED TO TODAY, exactly as Home and the Budget page are: every figure here is a claim on
  # the NEXT period, which is a fact about now rather than about the sidebar's month scrubber.
  #
  # IT REFUSES IN TWO STATES, and they are two different refusals rather than one guard said
  # twice. A user who has declared nothing has not asked a question this page could answer; a user
  # whose rules fit has asked it and got "yes". Sending both to the same sentence would tell the
  # second one to go and declare something they already declared.
  #
  # BOTH REFUSALS LAND ON /budget, which is where the two facts behind them live: the declaration
  # form is in that page's structural check block, and so is the button that leads back here the
  # moment the answer changes. A redirect to Home would put the user one screen away from either.
  #
  # `notice` rather than `alert`: neither state is an error. Arriving here covered is what the app
  # wants for you, and arriving undeclared is a step not yet taken.
  def show
    @presenter = SacrificePresenter.new(user: current_user, today: Date.current)
    return if @presenter.underwater?

    redirect_to budget_page_path, notice: refusal_for(@presenter)
  end

  private

  def refusal_for(presenter)
    return "Tell us how long a period is and what you typically bring in, and we can say what would have to give." unless
      presenter.declared?

    "Your rules already fit what you bring in, so there's nothing here to cut."
  end
end
