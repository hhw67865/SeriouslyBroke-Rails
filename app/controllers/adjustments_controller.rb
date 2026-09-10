# frozen_string_literal: true

class AdjustmentsController < ApplicationController
  include BudgetPageState

  def create
    rule = scoped_rule
    form = AdjustmentForm.new(rule: rule, params: params, name: helpers.rule_name(rule), today: current_user.today)
    if form.save
      redirect_to back_to(rule), notice: confirmation(form)
    else
      refuse_on_budget_page(form.error_sentence)
    end
  end

  def destroy
    adjustment = Adjustment.where(rule_id: Rule.for_user(current_user).select(:id)).find(params[:id])
    rule = adjustment.rule
    adjustment.destroy
    redirect_to back_to(rule), notice: removal(adjustment, rule)
  end

  private

  def back_to(rule) = budget_page_path(open: rule.category_id)
  def scoped_rule = Rule.for_user(current_user).find(params[:rule_id])

  def confirmation(form)
    money = helpers.number_to_currency(form.adjustment.amount.abs)
    name = form.name
    negative = form.adjustment.amount.negative?
    return "Skipped this period for #{name} — #{money} less set aside." if form.skip?

    if form.allowance?
      negative ? "Reduced #{name} by #{money} this period." : "Topped up #{name} by #{money} this period."
    else
      negative ? "Took back #{money} from #{name}." : "Set aside #{money} for #{name}."
    end
  end

  def removal(adjustment, rule)
    money = helpers.number_to_currency(adjustment.amount.abs)
    name = helpers.rule_name(rule)
    negative = adjustment.amount.negative?
    if rule.claim_calculator(today: current_user.today).allowance?
      negative ? "Removed the #{money} reduction on #{name}." : "Removed the #{money} top-up on #{name}."
    else
      negative ? "Removed the #{money} taken back from #{name}." : "Removed the #{money} set aside for #{name}."
    end
  end
end
