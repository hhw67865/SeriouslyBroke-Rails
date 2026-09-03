# frozen_string_literal: true

# SETTING MONEY ASIDE, TAKING IT BACK, TOPPING UP, REDUCING AND SKIPPING (computed-claims spec
# §3.3) — five words for one row, and this is the door all five go through.
#
# INHERITS BudgetPageController, NOT ApplicationController, for exactly BankAccountsController's
# reason: the failure path re-renders `budget_page/show`, whose bare partial renders (`render
# "fill_order"`) resolve against the RENDERING controller's view prefixes. Subclassing puts
# `budget_page/` in that chain and hands this class the page's own `#refuse` and `#build_presenter`
# — this action IS a Budget-page door, and the alternative is qualifying every partial name inside
# that page's views for a foreign controller's benefit. `show`, `update` and `reorder` are not
# routed here, so nothing is reachable through this controller but the two actions below.
#
# NOTHING PHYSICAL MOVES. There is no path from here to `account_movements` or to `pools`: the
# invariant `pot + Σ accounts == income − expenses` is blind to this table, which is what makes an
# adjustment free to be written and deleted without ever putting the two ledgers out of step.
class AdjustmentsController < BudgetPageController
  # POST /adjustments
  def create
    rule = scoped_rule
    adjustment = rule.adjustments.new(amount: amount_for(rule), date: chosen_date)

    if adjustment.save
      redirect_to budget_page_path, notice: confirmation(rule, adjustment)
    else
      # The RECORD's own sentence, and the page comes back at 422 with nothing written — the shape
      # every refusal on this screen takes (see BudgetPageController#refuse). A zero amount is the
      # one this can actually be: `Adjustment` refuses it in Ruby and the database refuses it again.
      refuse(adjustment.errors.full_messages.to_sentence)
    end
  end

  # DELETE /adjustments/1
  def destroy
    adjustment = scoped_adjustment
    adjustment.destroy

    redirect_to budget_page_path,
                notice: "Removed #{helpers.number_to_currency(adjustment.amount)} " \
                        "from #{helpers.budget_rule_name(adjustment.rule)} this period."
  end

  private

  # `Budget.for_user`, the app's ONE answer to which rules are a user's — so a crafted `rule_id` is
  # not found rather than found and refused.
  def scoped_rule = Budget.for_user(current_user).find(params[:rule_id])

  # THROUGH THE RULE, because `adjustments` carries no user column and inventing one would give
  # ownership two places to be wrong. The subquery is `Budget.for_user`'s own scope, so the delete
  # door and the write door agree about whose rules exist.
  def scoped_adjustment
    Adjustment.where(rule_id: Budget.for_user(current_user).select(:id)).find(params[:id])
  end

  # WHAT THE ROW IS WORTH, and the three ways a submission can say it:
  #
  #   * `skip` — the server computes it. §3.3's "skip a period = an adjustment of −planned dated
  #     today", and the planned share is a fact `ClaimCalculator` owns: carrying it in a hidden
  #     field would let a page rendered before another delta landed skip the wrong amount. A period
  #     that plans nothing yields a zero, which `Adjustment` refuses — the view hides the button
  #     there, and this is the backstop.
  #   * `amount_sign` — the form types a MAGNITUDE and the button pressed says the direction, which
  #     is what lets one input serve "top up" and "reduce" without asking the user to type a minus.
  #   * a bare signed `amount` — the route's own contract, which the buttons are one spelling of.
  def amount_for(rule)
    return -rule.claim_calculator(today: Date.current).planned_this_period if params[:skip].present?
    return -params[:amount].to_s.to_d.abs if params[:amount_sign].to_i.negative?

    params[:amount]
  end

  # THE DAY THE DELTA LANDS ON, IN THE OWNER'S ZONE (§3.3: it applies to the period CONTAINING its
  # date), and BOTH ARMS GET THERE THROUGH `Time.zone` — which `ApplicationController`'s
  # `around_action :use_user_timezone` has already set to the owner's.
  #
  #   * blank — `Time.current`, the owner's now. A UTC evening is already tomorrow in Tokyo, and
  #     `Date.current` here would be the same day by luck rather than by construction.
  #   * given — the string is assigned to the column and Rails' time-zone-aware attributes parse it
  #     in `Time.zone`, so "2026-09-12" is midnight in NEW YORK rather than at UTC. A `Time.zone
  #     .parse` of our own would be a second spelling of the cast that is already happening, and
  #     `adjustments_spec`'s New York example pins the behaviour either way.
  #
  # AN UNPARSEABLE VALUE CASTS TO nil AND IS REFUSED BY THE MODEL, never raised: `date` is
  # `presence`-validated, so garbage arrives as the same 422 every other bad field does.
  def chosen_date = params[:date].presence || Time.current

  # THE USER'S OWN FIVE WORDS, chosen by the sign and by what the rule IS — a rate rule's envelope
  # is topped up or reduced for this period, an accruing rule's fund is set aside into or taken back
  # out of. The word "adjustment" appears nowhere a user can read it; it is the table's name and the
  # spec's, not the app's.
  def confirmation(rule, adjustment)
    money = helpers.number_to_currency(adjustment.amount.abs)
    name = helpers.budget_rule_name(rule)
    return "Skipped this period for #{name} — #{money} less set aside." if params[:skip].present?

    if rule.claim_calculator(today: Date.current).rate?
      adjustment.amount.negative? ? "Reduced #{name} by #{money} this period." : "Topped up #{name} by #{money} this period."
    else
      adjustment.amount.negative? ? "Took back #{money} from #{name}." : "Set aside #{money} for #{name}."
    end
  end
end
