# frozen_string_literal: true

class SacrificesController < ApplicationController
  def show
    @presenter = presenter
    return if @presenter.underwater?

    redirect_to budget_page_path, notice: refusal_for(@presenter)
  end

  def update
    cuts = SacrificeCuts.new(current_user, cuts: dialled_cuts, target_cuts: dialled_target_cuts, today: current_user.today)
    return redirect_to(*landing_for(cuts)) if cuts.apply

    @presenter = presenter
    @cut_errors = cuts.errors
    @typed = dialled_cuts
    @typed_targets = dialled_target_cuts
    render :show, status: :unprocessable_content
  end

  private

  # Built fresh per call: after `cuts.apply` writes, the rules and targets behind it have changed,
  # and this is the presenter that reads them back.
  def presenter = SacrificePresenter.new(user: current_user, today: current_user.today)

  def refusal_for(presenter)
    return "Set your period on the Budget page and log a period of income, and we can say what would have to give." unless presenter.declared?

    "Your savings and budget already fit what you bring in, so there's nothing here to cut."
  end

  def dialled_cuts = params.permit(cuts: {})[:cuts].to_h
  def dialled_target_cuts = params.permit(target_cuts: {})[:target_cuts].to_h

  def landing_for(cuts)
    fresh = presenter
    saved = "Saved — #{helpers.pluralize(cuts.count, "cut")}."
    return [sacrifice_path, { notice: "#{saved} Still #{helpers.number_to_currency(fresh.gap)} underwater a period." }] if fresh.underwater?

    [budget_page_path, { notice: "#{saved} Your savings and budget now need #{helpers.number_to_currency(fresh.budget + fresh.savings)} a period." }]
  end
end
