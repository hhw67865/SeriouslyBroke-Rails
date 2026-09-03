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
  #
  # `AdjustmentForm` OWNS WHAT THE SUBMISSION MEANS — which amount the three spellings come to,
  # which day it lands on, and whether the rule's own walk can count that day (fix round MED-1).
  # This action owns only the two things a controller owns: whose rule it is, and which sentence
  # the user reads afterwards.
  def create
    rule = scoped_rule
    form = AdjustmentForm.new(
      rule: rule, params: params, name: helpers.budget_rule_name(rule), today: Date.current
    )

    if form.save
      redirect_to budget_page_path, notice: confirmation(form)
    else
      # The FORM's sentence — the record's own where a column is at fault, its own where the date
      # is out of the rule's reach — and the page comes back at 422 with nothing written, the shape
      # every refusal on this screen takes (see BudgetPageController#refuse).
      refuse(form.error_sentence)
    end
  end

  # DELETE /adjustments/1
  def destroy
    adjustment = scoped_adjustment
    rule = adjustment.rule
    adjustment.destroy

    redirect_to budget_page_path, notice: removal(adjustment, rule)
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

  # THE USER'S OWN FIVE WORDS, chosen by the sign and by what the rule IS — a rate rule's envelope
  # is topped up or reduced for this period, an accruing rule's fund is set aside into or taken back
  # out of. The word "adjustment" appears nowhere a user can read it; it is the table's name and the
  # spec's, not the app's.
  #
  # THE FIGURE IS A MAGNITUDE AND THE DIRECTION IS A WORD, on all five — `.abs` and a verb, never a
  # minus sign left to do a verb's work.
  def confirmation(form)
    money = helpers.number_to_currency(form.adjustment.amount.abs)
    name = form.name
    negative = form.adjustment.amount.negative?
    return "Skipped this period for #{name} — #{money} less set aside." if form.skip?

    if form.rate?
      negative ? "Reduced #{name} by #{money} this period." : "Topped up #{name} by #{money} this period."
    else
      negative ? "Took back #{money} from #{name}." : "Set aside #{money} for #{name}."
    end
  end

  # ** THE SAME FIVE WORDS SAID BACKWARD (fix round LOW-2). ** The destroy flash printed
  # `number_to_currency` of the SIGNED amount — "Removed -$150.00 from Vacation this period" — a
  # minus doing a verb's work on the one screen where the user has just pressed Remove, and on the
  # one row where the sign is the whole meaning. It now names the direction in the vocabulary the
  # four writing flashes use, off the same two facts they branch on: the rule's shape and the sign.
  #
  # `rule` IS CAPTURED BEFORE THE DESTROY, not read back off the frozen record.
  # `ClaimCalculator#rate?` reads `anchor_date` and the category's `target_amount` and no more, so
  # asking the shape here costs no statement.
  def removal(adjustment, rule)
    money = helpers.number_to_currency(adjustment.amount.abs)
    name = helpers.budget_rule_name(rule)
    negative = adjustment.amount.negative?

    if rule.claim_calculator(today: Date.current).rate?
      negative ? "Removed the #{money} reduction on #{name}." : "Removed the #{money} top-up on #{name}."
    else
      negative ? "Removed the #{money} taken back from #{name}." : "Removed the #{money} set aside for #{name}."
    end
  end
end
