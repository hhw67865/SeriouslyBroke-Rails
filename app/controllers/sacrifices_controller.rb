# frozen_string_literal: true

class SacrificesController < ApplicationController
  def show
    @presenter = SacrificePresenter.new(user: current_user, today: current_user.today)
    return if @presenter.underwater?

    redirect_to budget_page_path, notice: refusal_for(@presenter)
  end

  private

  def refusal_for(presenter)
    return "Set your period on the Budget page and log a period of income, and we can say what would have to give." unless presenter.declared?

    "Your rules already fit what you bring in, so there's nothing here to cut."
  end
end
