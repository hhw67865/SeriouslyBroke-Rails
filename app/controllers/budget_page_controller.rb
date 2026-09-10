# frozen_string_literal: true

class BudgetPageController < ApplicationController
  include BudgetPageState

  def show
    @presenter = build_budget_page
  end

  def update
    change = CadenceChange.new(user: current_user, declaration: declaration_params)
    return offer_scaling(change) if change.offered? && scale_choice.nil?

    if change.apply(scale: scale_choice)
      redirect_to budget_page_path, notice: saved_notice(change)
    else
      @presenter = build_budget_page(user: User.find(current_user.id), declaration: current_user)
      render :show, status: :unprocessable_content
    end
  end

  def reorder
    ordered = Category.apply_fill_order(user: current_user, category_ids: params.permit(category_ids: [])[:category_ids])
    return redirect_to(budget_page_path, notice: "Your money fills them in that order now.") if ordered

    refuse_on_budget_page("That order didn't match your categories — nothing was changed. Reload and try again.")
  end

  def income
    ids = params.permit(regular_category_ids: [])[:regular_category_ids] || []
    Category.choose_regular_income(user: current_user, category_ids: ids)
    redirect_to budget_page_path, notice: "Saved — your typical income is measured from those categories now."
  end

  private

  def offer_scaling(change)
    @cadence_change = change
    @presenter = build_budget_page
    render :show, status: :unprocessable_content
  end

  def scale_choice
    return nil if params[:scale].blank?

    params[:scale] == "1"
  end

  def saved_notice(change)
    return "Your period is saved — every figure below is re-derived." unless change.scaled?

    "Your period is saved and your per-period amounts were scaled to it — every figure below is re-derived."
  end

  def declaration_params = params.expect(user: [:period_cadence, :period_anchor_date])
end
