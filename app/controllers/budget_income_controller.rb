# frozen_string_literal: true

class BudgetIncomeController < ApplicationController
  def show
    @presenter = BudgetIncomePresenter.new(user: current_user)
  end

  def update
    change = CadenceChange.new(user: current_user, declaration: declaration_params)
    return offer_scaling(change) if change.offered? && scale_choice.nil?

    if apply(change)
      redirect_to budget_income_path, notice: saved_notice(change)
    else
      refuse
    end
  end

  private

  def apply(change)
    saved = false
    ActiveRecord::Base.transaction do
      saved = change.apply(scale: scale_choice)
      raise ActiveRecord::Rollback unless saved

      Category.choose_regular_income(user: current_user, category_ids: regular_ids)
    end
    saved
  end

  def refuse
    @presenter = BudgetIncomePresenter.new(user: User.find(current_user.id), declaration: current_user)
    render :show, status: :unprocessable_content
  end

  def offer_scaling(change)
    @cadence_change = change
    @regular_ids = regular_ids
    @presenter = BudgetIncomePresenter.new(user: current_user)
    render :show, status: :unprocessable_content
  end

  def scale_choice
    return nil if params[:scale].blank?

    params[:scale] == "1"
  end

  def saved_notice(change)
    return "Your period is saved — every figure is re-derived." unless change.scaled?

    "Your period is saved and your per-period amounts were scaled to it — every figure is re-derived."
  end

  def declaration_params = params.expect(user: [:period_cadence, :period_anchor_date])
  def regular_ids = params.permit(regular_category_ids: [])[:regular_category_ids] || []
end
