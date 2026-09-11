# frozen_string_literal: true

class AdjustmentsController < ApplicationController
  include HomeState
  include SavingsPageState

  # Where each source is found, through current_user: a foreign id is not found rather than refused.
  SOURCE_SCOPES = {
    "Rule" => ->(user) { Rule.for_user(user) },
    "Account" => ->(user) { user.accounts }
  }.freeze

  def create
    source = scoped_source
    return head :unprocessable_content if source.nil?

    form = AdjustmentForm.new(source: source, params: params, name: name_for(source), today: current_user.today)
    if form.save
      redirect_to back_to(source), notice: confirmation(form)
    else
      refuse(source, form.error_sentence)
    end
  end

  def destroy
    adjustment = Adjustment.find(params[:id])
    raise ActiveRecord::RecordNotFound unless adjustment.user == current_user

    source = adjustment.source
    adjustment.destroy
    redirect_to back_to(source), notice: removal(adjustment, source)
  end

  private

  def scoped_source
    scope = SOURCE_SCOPES[params[:source_type]]
    scope&.call(current_user)&.find(params[:source_id])
  end

  def name_for(source) = source.is_a?(Rule) ? helpers.rule_name(source) : source.name

  def back_to(source)
    return root_path(anchor: "block-#{source.category_id}") if source.is_a?(Rule)

    params[:return] == "home" ? root_path(anchor: "savings-#{source.id}") : savings_path
  end

  def refuse(source, message)
    source.is_a?(Rule) || params[:return] == "home" ? refuse_on_home(message) : refuse_on_savings_page(message)
  end

  def confirmation(form)
    money = helpers.number_to_currency(form.adjustment.amount.abs)
    name = form.name
    negative = form.adjustment.amount.negative?
    return "Skipped this period for #{name} — #{money} less #{form.savings? ? "owed" : "set aside"}." if form.skip?
    return "Reduced what #{name} is owed by #{money} this period." if form.savings?

    if form.allowance?
      negative ? "Reduced #{name} by #{money} this period." : "Topped up #{name} by #{money} this period."
    else
      negative ? "Took back #{money} from #{name}." : "Set aside #{money} for #{name}."
    end
  end

  def removal(adjustment, source)
    money = helpers.number_to_currency(adjustment.amount.abs)
    name = name_for(source)
    negative = adjustment.amount.negative?
    return "Removed the #{money} reduction on #{name}." if source.is_a?(Account)

    if source.claim_calculator(today: current_user.today).allowance?
      negative ? "Removed the #{money} reduction on #{name}." : "Removed the #{money} top-up on #{name}."
    else
      negative ? "Removed the #{money} taken back from #{name}." : "Removed the #{money} set aside for #{name}."
    end
  end
end
