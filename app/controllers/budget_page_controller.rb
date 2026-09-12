# frozen_string_literal: true

class BudgetPageController < ApplicationController
  include BudgetPageState

  def show
    @presenter = build_budget_page
  end

  def reorder
    ordered = Category.apply_fill_order(user: current_user, category_ids: params.permit(category_ids: [])[:category_ids])
    return redirect_to(budget_page_path, notice: "Your money fills them in that order now.") if ordered

    refuse_on_budget_page("That order didn't match your categories — nothing was changed. Reload and try again.")
  end
end
