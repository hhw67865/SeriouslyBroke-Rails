# frozen_string_literal: true

# The Budget page (spec §8): the rules themselves, not the money they move.
#
# A singular non-RESTful controller rather than an action on BudgetsController, because the two
# answer different questions: `budgets#index` would be a list of Budget rows, and this page is a
# reading of every rule GROUPED by the category it fills and ordered by when the money arrives. The
# route is `get "budget"`, named `budget_page` — `budget_path` already belongs to the member
# routes of `resources :budgets`.
class BudgetPageController < ApplicationController
  # Anchored to today rather than to the sidebar's month scrubber, exactly as Home is: every
  # figure here is about the next period's funding, which is a fact about now.
  def show
    @presenter = build_presenter
  end

  # THE DECLARATION: period and typical income, the two facts every figure on this page divides
  # by. `current_user`, never a `User.find(params[:id])` — the record being written is the one
  # signed in and there is no id on the wire to get wrong.
  #
  # A FAILED SAVE RE-RENDERS THIS PAGE, not a form of its own — 422, because nothing was written.
  #
  # TWO USER OBJECTS ON THE FAILURE PATH, and the split is a defect the browser caught. A failed
  # `update` leaves the REJECTED values on `current_user` in memory: after submitting a cadence
  # with no anchor, `current_user.typical_income` reads $2,400 and `period_cadence` reads
  # "biweekly" though the row holds neither. Handing that object to the presenter rendered the
  # full structural check — "Your rules need $520.00 a period / You typically bring in $2,400.00 /
  # Left over $1,880.00 → buffer" — computed from a declaration the database had just refused,
  # under an error message saying the save had failed. Reloading the page made all three lines
  # vanish.
  #
  # So the FIGURES read a clean reload of the row (what is actually true), and the FORM keeps the
  # dirty object (what the user typed, plus its errors) so nothing they entered is thrown away.
  # A separate instance rather than `current_user.reload`, which would discard both.
  def update
    if current_user.update(declaration_params)
      redirect_to budget_page_path, notice: "Your period and income are saved — every figure below is re-derived."
    else
      @presenter = BudgetPagePresenter.new(
        user: User.find(current_user.id),
        today: Date.current,
        declaration: current_user
      )
      render :show, status: :unprocessable_content
    end
  end

  # THE FILL ORDER (spec §8: "drag-ordered — this is where funding priority is set"). The user's
  # rule-carrying categories arrive as `category_ids[]` in their new order and
  # `Category.apply_fill_order` writes `priority: index` over exactly that list, or refuses the
  # whole thing.
  #
  # ONE LIST, WHERE THERE WERE BANDS (two-ledger spec §2). The wire used to carry `pool_ids[]` for
  # ONE ACCOUNT, because priority was only compared inside an account; `AllocationCalculator` fills
  # every holder off one root now, so the whole page is one order and one reorder.
  #
  # THE SAME SCOPING DISCIPLINE AS #update, one level down: every id goes through
  # `current_user.categories` inside the model method, so an id that is not this user's is not found
  # rather than found and refused — and the refusal is indistinguishable from the one a stale
  # page gets, which is the right answer for both.
  #
  # A REFUSAL RE-RENDERS THIS PAGE AT 422, as a failed declaration does, because nothing was
  # written and the order on screen is still the order in the database — there is nothing to
  # redirect to that would say more.
  #
  # A ROW THAT WAS ALREADY INVALID IS A REFUSAL, NOT A 500. `Category.apply_fill_order` writes
  # through `update!`, so a category carrying a pre-existing validation failure — a name emptied by
  # a data fix, a `priority` backfilled to NULL — raises RecordInvalid, rolls the whole reindex
  # back, and would otherwise reach the user as a crash on a button they were right to press. It is
  # the same outcome as every other refusal (nothing written, page re-rendered at 422) and it says
  # WHICH row, because that row is the only thing they can fix.
  def reorder
    ordered = Category.apply_fill_order(user: current_user, category_ids: params.permit(category_ids: [])[:category_ids])

    return redirect_to(budget_page_path, notice: "Your money fills them in that order now.") if ordered

    refuse("That order didn't match your categories — nothing was changed. Reload and try again.")
  rescue ActiveRecord::RecordInvalid => e
    refuse(
      "#{e.record.name} could not be saved " \
      "(#{e.record.errors.full_messages.to_sentence.downcase}), so nothing was changed."
    )
  end

  private

  # One refusal, one shape: nothing was written, so the page comes back as it stands with the
  # reason above it. 422 rather than a redirect, as a failed declaration is — there is nothing to
  # redirect to that would say more than the order already on screen does.
  def refuse(message)
    flash.now[:alert] = message
    @presenter = build_presenter
    render :show, status: :unprocessable_content
  end

  def build_presenter = BudgetPagePresenter.new(user: current_user, today: Date.current)

  # EXACTLY THREE PARAMS, and the list is the whole security boundary here. `current_user.update`
  # writes the signed-in user's own row, so ownership is never in question — but `User` carries
  # `email`, `encrypted_password`, `default_account_id` and `theme` on the same record, and a
  # mass-assignment from this form must reach none of them. A fourth key is dropped by
  # `expect`/`permit` rather than raising, which is the behaviour a real submission with a stale
  # field should get; spec/requests/budget_page_spec.rb pins that it is dropped and not written.
  #
  # `User` already validates all three (income > 0 allow_nil; anchor presence required whenever a
  # cadence is set), so this list permits and the model refuses — no second validation here.
  def declaration_params
    params.expect(user: [:typical_income, :period_cadence, :period_anchor_date])
  end
end
