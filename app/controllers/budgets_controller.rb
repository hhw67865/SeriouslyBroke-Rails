# frozen_string_literal: true

class BudgetsController < ApplicationController
  before_action :set_budget, only: [:edit, :update, :destroy]
  before_action :set_category, only: [:new, :create]
  before_action :set_envelope, only: [:new, :create]

  # EVERY COLUMN THIS FORM MAY WRITE. `basis`, `interval_months`, `anchor_date` and `item_id`
  # joined the list for §8's suggestion panel: a proposed dated bill is "$85 every month, next due
  # Sep 21, paying the Phone item", and none of those four is derivable from the amount.
  #
  # Each carries a validation consequence — `shape_must_be_valid` on the first three,
  # `item_must_belong_to_pool` and `item_must_not_be_claimed` on the last — so shape is answered by
  # `Budget` and only OWNERSHIP is answered below.
  BUDGET_FIELDS = [:amount, :category_id, :pool_id, :prorated, :basis, :interval_months, :anchor_date, :item_id].freeze

  # GET /budgets/new
  #
  # PREFILLED FROM THE QUERY STRING when the suggestion panel sent the user here, and the prefill
  # goes through the same ownership scoping the POST does — a stranger's `item_id` in a GET would
  # render THEIR item's name on this user's form, which is the read-shaped half of the same leak.
  def new
    @budget = @category ? @category.build_budget : Budget.new
    @budget.assign_attributes(prefill_attributes)
  end

  # GET /budgets/1/edit
  #
  # A DRIFT SUGGESTION PREFILLS THE AMOUNT AND THE FORM SHOWS THE CURRENT ONE BESIDE IT. The
  # figure arrives in THE RULE'S OWN UNIT — `SuggestionEngine#rule_unit_amount` inverts
  # `Budget#steady_ask` before putting it on the wire, precisely so nothing downstream converts —
  # so this assigns it and the form LABELS it with the rule's basis. Nothing is written: the
  # assignment is to the in-memory record the form renders, and the user still has to submit.
  def edit
    @current_amount = @budget.amount
    @budget.amount = prefill_attributes[:amount] if prefill_attributes.key?(:amount)
  end

  # POST /budgets
  #
  # ONE FORM AND ONE POST for the whole accept flow. What the envelope half makes happen is
  # `BudgetProposal`'s to explain and this action does not restate it; here it is only that both
  # outcomes render the same two branches they always did.
  def create
    @budget = Budget.new(budget_params)

    if BudgetProposal.new(budget: @budget, envelope: @envelope).save
      redirect_to owner_path(@budget), notice: "Budget was successfully created."
    else
      render :new, status: :unprocessable_content
    end
  end

  # PATCH/PUT /budgets/1
  def update
    if @budget.update(budget_params)
      redirect_to owner_path(@budget), notice: "Budget was successfully updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  # DELETE /budgets/1
  def destroy
    owner = owner_path(@budget)
    @budget.destroy
    redirect_to owner, notice: "Budget was successfully deleted."
  end

  private

  # `Budget.for_user`, not `current_user.budgets` — the association walks the category link
  # only, so it 404s every pool-mode rule, which is every rule the Budget page manages.
  # Still a scoped lookup, so another user's rule raises RecordNotFound exactly as before.
  def set_budget
    @budget = Budget.for_user(current_user).find(params[:id])
  end

  # WHERE A CHANGED RULE SENDS YOU: the screen that owns it. A rule has exactly one owner
  # (Budget#exactly_one_owner), and until #set_budget was widened only one of the two was
  # ever reachable here — so `category_path(@budget.category)` was safe by accident.
  #
  # It is not safe now. A pool-mode rule has no category at all, and `category_path(nil)`
  # raises UrlGenerationError: a 500 raised AFTER the update or destroy had already been
  # written, on precisely the rules the widened reader just made reachable. Widening a
  # reader must not open a crash path behind it.
  #
  # THE POOL-MODE DESTINATION IS THE BUDGET PAGE, not `pool_path`. The pool page was a floor
  # while nothing else could render a pool-mode rule; §8's page is where every rule the user
  # owns now lives, and it is the page the Edit link was clicked FROM. Returning to the pool
  # would answer a rule change with a screen that says nothing about rules. Category-mode
  # rules still go back to their category, which is still the only screen that renders one.
  #
  # #destroy takes the path BEFORE the delete, and that ordering is DEFENSIVE, NOT LOAD-BEARING
  # — an earlier version of this comment claimed otherwise and was wrong. Measured: a destroyed
  # Budget is frozen but keeps its `category_id`/`pool_id`, and the owner row is not touched by
  # the child's delete, so `owner_path` resolves to the same URL after the destroy as before it.
  # Taking it first states that the destination is a fact about the rule as it stood, and it
  # survives a future `dependent:` or callback that does start clearing the link — but nothing
  # today depends on the order, and no example fails if it is reversed.
  def owner_path(budget)
    budget.category ? category_path(budget.category) : budget_page_path
  end

  def set_category
    @category = current_user.categories.expenses.budgetable.find(params[:category_id]) if params[:category_id]
  end

  # THE WRITE SIDE OF #set_budget'S QUESTION, and it has to be asked here because nothing else
  # asks it. `category_id` is a wire parameter, and `Budget` cannot object to a foreign
  # category — it validates that a category is an expense and pool-free, never WHOSE it is.
  # Unscoped, `POST /budgets` with a stranger's category id wrote a funding rule onto their
  # category, and `PATCH` re-parented one of mine onto theirs; both then rendered on their
  # page. A scoped read beside an unscoped write is ownership on the way in only.
  #
  # WHERE THE LINE SITS, deliberately: `current_user.categories` and nothing more. Ownership
  # is the controller's question. Expense-ness and pool-freeness are #category_must_be_expense
  # and #category_must_not_have_pool, which already answer them — stacking `.expenses
  # .budgetable` here would make this a second reader of both, and would turn a legible form
  # error on the user's OWN income category into a 404 indistinguishable from a stranger's id.
  # `set_category` scopes harder because it answers a different question: which categories may
  # be OFFERED the form, not which a save may name.
  #
  # `pool_id` IS NOW PERMITTED, and the same line is drawn on it. The Budget page links every
  # pool-mode rule to this form, so the form submits the rule's own pool back — and the moment
  # the parameter is permitted, "whose pool is this" becomes exactly the question `category_id`
  # already had to answer. Two request examples pinned `pool_id` as inert while it was
  # unpermitted; widening the list trips them by design, and they are rewritten into the
  # both-direction ownership pair below.
  #
  # `current_user.pools` and nothing more, for the same reason as categories: ownership is the
  # controller's question, while "not an account", "the right shape" and "the item belongs to
  # this pool" are Budget's own validations. Scoping to `.budget_pools` here would turn a user
  # naming their OWN account into a 404 — their record vanishing — where the model gives a
  # legible 422.
  def budget_params = scoped_owners(params.expect(budget: BUDGET_FIELDS))

  # THE SAME LIST AND THE SAME SCOPING, read off a GET. `expect` raises ParameterMissing on a
  # bare `/budgets/new`, which is the ordinary way this form is reached, so the absence of the
  # key is an empty prefill rather than a 400.
  def prefill_attributes
    @prefill_attributes ||=
      if params[:budget].blank?
        {}
      else
        scoped_owners(params.expect(budget: BUDGET_FIELDS))
      end
  end

  # `item_id` IS THE THIRD APPEARANCE OF §7a'S CLASS, AND IT IS THE SHARPEST OF THE THREE. A rule
  # names the item it pays; `Budget` validates that the item sits in a category pointing at the
  # rule's pool, never WHOSE item it is. Unscoped, `POST /budgets` with a stranger's item id
  # writes a funding rule against THEIR spending — the rule then reads their entries through
  # `BudgetCalculator#paid_since_anchor` and reports their bills as paid or unpaid on this user's
  # page. `current_user.items` walks the user's categories, so a stranger's id is not found.
  #
  # The line stays exactly where Task 2 drew it: whose, here; what shape, in the model. An item
  # of the user's OWN in the wrong category is `item_must_belong_to_pool`'s 422, not a 404.
  def scoped_owners(permitted)
    permitted = scoped_owner(permitted, :category_id, current_user.categories)
    permitted = scoped_owner(permitted, :pool_id, current_user.pools)
    scoped_owner(permitted, :item_id, current_user.items)
  end

  # THE OPTIONAL ENVELOPE HALF (amendment A): the pool a proposing suggestion would create and the
  # category it would re-point at it. Present only when the panel sent one — every other request
  # to this controller leaves `@envelope` nil and `BudgetProposal` degrades to `budget.save`.
  #
  # `envelope[category_id]` RATHER THAN THE FORM'S OWN `category_id`, and the rename is
  # load-bearing: `#set_category` already reads a top-level `category_id` as the OWNER of a
  # category-mode cap, and the engine's payload means something entirely different by the same
  # word — the category to be MOVED into the new envelope. One key with two meanings on one form
  # is a rule that quietly caps a category when it was asked to fund an envelope.
  #
  # KEYED ON THE CATEGORY, not on the presence of the `envelope` key: without a category there is
  # nothing to re-point, so there is no envelope half — and the rule then has no owner at all,
  # which `Budget#exactly_one_owner` answers with a legible 422 rather than this raising.
  #
  # `pool_type` IS NOT PERMITTED. See BudgetProposal#create_envelope.
  #
  # Ownership, both ids, through `current_user`: `find` on the category so a stranger's is the
  # same 404 every other owner id gives, and the account through `current_user.pools` — not
  # `.accounts` — so that a user naming one of their OWN envelopes gets `Pool`'s legible
  # "Account must be an account" instead of their own record vanishing. `account_id` may be
  # legitimately blank (the engine reads `users.default_account_id`, which is nullable); the form
  # asks for one and `require_account_for_budget_pools` refuses the blank.
  def set_envelope
    return if params[:envelope].blank?

    permitted = params.expect(envelope: [:name, :account_id, :category_id])
    return if permitted[:category_id].blank?

    @envelope = build_envelope(permitted)

    # RESOLVED ONCE, HERE, so the form and the save read the same answer. Without it the form
    # headed "A new Utilities envelope" and offered an account picker on the very path where
    # `BudgetProposal` was going to JOIN an existing envelope and never look at the account — an
    # inert control under a false heading, one click after a panel sentence saying the opposite.
    # `Envelope#existing` is the one reader; this only keeps it from being asked four times while
    # the form renders.
    @joined_envelope = @envelope.existing
  end

  def build_envelope(permitted)
    BudgetProposal::Envelope.new(
      name: permitted[:name],
      account: permitted[:account_id].presence && current_user.pools.find(permitted[:account_id]),
      category: current_user.categories.find(permitted[:category_id])
    )
  end

  # `find`, so a stranger's id raises RecordNotFound and arrives as the same 404 #set_budget
  # gives. Skipped when blank, because a blank owner is the other mode's form submitting its
  # empty picker and an owner-less create re-rendering — both of which Budget already answers
  # (#exactly_one_owner), and neither of which is a stranger's id.
  def scoped_owner(permitted, key, scope)
    return permitted if permitted[key].blank?

    permitted.merge(key => scope.find(permitted[key]).id)
  end
end
