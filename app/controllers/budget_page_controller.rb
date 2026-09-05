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
  # full structural check — "Your rules need $520.00 a period / You typically bring in $2,400.00 a
  # period / Left over $1,880.00 free" — computed from a declaration the database had just refused,
  # under an error message saying the save had failed. Reloading the page made all three lines
  # vanish.
  #
  # So the FIGURES read a clean reload of the row (what is actually true), and the FORM keeps the
  # dirty object (what the user typed, plus its errors) so nothing they entered is thrown away.
  # A separate instance rather than `current_user.reload`, which would discard both.
  # ** THE CADENCE OFFER (computed-claims spec §3.5), AND IT SITS IN FRONT OF THE SAVE. ** A rate
  # rule's amount is denominated in PERIODS, so moving from monthly to biweekly changes what "$400"
  # means without changing a character of it. The app cannot know which the user meant, so it asks
  # once — the list, the two buttons, and then `CadenceChange#apply` writes the cadence and their
  # answer TOGETHER or writes neither. A user with no rate rules is never asked (`#offered?`).
  #
  # 422 ON THE CONFIRM STEP, and it is the same law every other refusal on this page follows:
  # NOTHING WAS WRITTEN, so the page comes back as it stands with the question above it. It is also
  # the only status Turbo will render a form response at without a redirect, so a 200 here would
  # leave the user looking at their unchanged page with no question on it at all.
  def update
    change = CadenceChange.new(user: current_user, declaration: declaration_params)

    return offer_scaling(change) if change.offered? && scale_choice.nil?

    if change.apply(scale: scale_choice)
      redirect_to budget_page_path, notice: saved_notice(change)
    else
      # THE DAY COMES OFF THE SAME CLEAN ROW THE FIGURES DO (fix round 2 — LOW-1). `User#today` reads
      # the owner's `timezone` column, and `current_user` in this branch is the DIRTY object — the one
      # carrying what the user just typed and failed to save — which is exactly what the reload above
      # exists to keep away from the figures. One `owner` local, so the two cannot be handed different
      # rows.
      owner = User.find(current_user.id)
      @presenter = build_presenter(user: owner, declaration: current_user)
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

  # THE QUESTION, ON THIS PAGE, WITH NOTHING WRITTEN. `build_presenter` reads `current_user`
  # unchanged — the declaration was never applied, so unlike the failure path below there is no
  # dirty object here and every figure on the page is still true.
  def offer_scaling(change)
    @cadence_change = change
    @presenter = build_presenter
    render :show, status: :unprocessable_content
  end

  # THE USER'S ANSWER, or nil for "not asked yet". Three states and not two: a missing `scale` is
  # what triggers the offer, and `"0"` is a real answer — "keep my amounts" — that must reach
  # `#apply` as false rather than as absent, or the confirm would loop forever on the same screen.
  def scale_choice
    return nil if params[:scale].blank?

    params[:scale] == "1"
  end

  # The original sentence on the ordinary path, so nothing that already reads for it moves; the
  # scaled path says the second thing that happened, because a user who pressed "Scale them" needs
  # the page to confirm that the amounts moved and not only the period.
  #
  # ** IT BRANCHES ON WHAT `#apply` DID, NEVER ON `scale_choice` (fix round 2, NEW-1). ** The
  # parameter is the user's ANSWER, and `#apply` acts on it only where the question would have been
  # asked (`CadenceChange#offered?`) — so a crafted `scale=1` on a first cadence, and a real change
  # on a user with no per-period rule, each saved the period, rewrote nothing, and were told "your
  # per-period amounts were scaled to it". `#scaled?` is the write reporting itself.
  def saved_notice(change)
    return "Your period and income are saved — every figure below is re-derived." unless change.scaled?

    "Your period is saved and your per-period amounts were scaled to it — every figure below is re-derived."
  end

  # One refusal, one shape: nothing was written, so the page comes back as it stands with the
  # reason above it. 422 rather than a redirect, as a failed declaration is — there is nothing to
  # redirect to that would say more than the order already on screen does.
  def refuse(message)
    flash.now[:alert] = message
    @presenter = build_presenter
    render :show, status: :unprocessable_content
  end

  # ** THE TWO THINGS THE URL SAYS ABOUT THIS RENDER (two-shapes spec §4). **
  #
  # `open` IS WHICH CATEGORY IS EXPANDED, and it is a query parameter rather than session state for
  # two reasons: one category open at a time is a fact about the PAGE, not about the user, and a
  # link that carries it is what makes expanding work with scripting off. `category_list_controller`
  # is the enhancement — it flips the panels in place and remembers the last one per viewer — and
  # the server-rendered one wins on load.
  #
  # `declare` IS THE DECLARATION FORM, hidden behind the income tile's "change" (§4). It used to be
  # permanently open under a block of prose, which put a three-field settings form in the middle of
  # the one screen that is about rules.
  #
  # NEITHER IS TRUSTED WITH ANYTHING: `open` is compared as a string against the ids the page
  # itself rendered (`BudgetPagePresenter#open?`), so an id that is not this user's simply matches
  # no row, and `declare` is a boolean read of presence.
  def build_presenter(user: current_user, declaration: nil)
    BudgetPagePresenter.new(
      user: user,
      today: user.today,
      declaration: declaration,
      open_category_id: params[:open],
      declaring: params[:declare].present?
    )
  end

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
