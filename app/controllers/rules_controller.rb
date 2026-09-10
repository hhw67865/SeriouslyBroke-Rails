# frozen_string_literal: true

class RulesController < ApplicationController
  before_action :set_rule, only: [:edit, :update, :destroy, :spending]
  before_action :set_previewed_rule, only: [:preview]

  NEW_NEEDS_A_CATEGORY = "Open a category on the Budget page to write a rule for it."

  def new
    @rule_form = RuleForm.new(current_user, prefill)
    return redirect_to budget_page_path, alert: NEW_NEEDS_A_CATEGORY if @rule_form.rule.category.blank?

    prepare_page
  end

  def edit
    @rule_form = RuleForm.new(current_user, RuleForm.from(@rule), rule: @rule)
    prepare_page
  end

  def create
    @rule_form = RuleForm.new(current_user, rule_params)
    write(:new, "Rule was successfully created.")
  end

  def update
    @rule_form = RuleForm.new(current_user, RuleForm.from(@rule).merge(update_params), rule: @rule)
    write(:edit, "Rule was successfully updated.")
  end

  def preview
    words = @rule ? RuleForm.from(@rule).merge(scoped(payload.except(:category_id))) : scoped(payload)
    @rule_form = RuleForm.new(current_user, words, rule: @rule)
    @preview = RulePreview.new(@rule_form, user: current_user)
    return render partial: "rules/preview", locals: { preview: @preview } if turbo_frame_request?

    prepare_page
    render @rule ? :edit : :new
  end

  # The entries behind one rule's figure — a lazy frame under the row, or its own page.
  def spending
    @spending = RuleSpendingPresenter.new(@rule, today: current_user.today)
    return render partial: "rules/spending", locals: { spending: @spending }, layout: false if turbo_frame_request?

    render :spending
  end

  # The category is read before the destroy, so the page it returns to still opens on the panel the
  # button was pressed in.
  def destroy
    category_id = @rule.category_id
    @rule.destroy
    redirect_to budget_page_path(open: category_id), notice: "Rule deleted."
  end

  private

  def write(template, notice)
    if @rule_form.save
      redirect_to budget_page_path(open: @rule_form.rule.category_id), notice: notice
    else
      prepare_page
      render template, status: :unprocessable_content
    end
  end

  def set_rule = @rule = Rule.for_user(current_user).find(params[:id])

  def set_previewed_rule
    @rule = Rule.for_user(current_user).find(params[:id]) if params[:id].present?
  end

  def prepare_page
    @category = @rule_form.rule.category
    @preview = RulePreview.new(@rule_form, user: current_user)
  end

  def prefill
    scoped({ category_id: params[:category_id].presence }.compact.merge(payload))
  end

  def payload = params[:rule].blank? ? {} : params.expect(rule: RuleForm::FIELDS).to_h.symbolize_keys
  def rule_params = scoped(params.expect(rule: RuleForm::FIELDS).to_h.symbolize_keys)
  def update_params = scoped(params.expect(rule: RuleForm::FIELDS - [:category_id]).to_h.symbolize_keys)

  # Ids are looked up through current_user so a foreign id 404s instead of writing.
  def scoped(words)
    words[:category_id] = current_user.categories.find(words[:category_id]).id if words[:category_id].present?
    words[:item_id] = current_user.items.find(words[:item_id]).id if words[:item_id].present?
    words
  end
end
