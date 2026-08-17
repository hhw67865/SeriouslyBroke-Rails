# frozen_string_literal: true

class BudgetsController < ApplicationController
  before_action :set_budget, only: [:edit, :update, :destroy]
  before_action :set_envelope, only: [:new, :create]

  # EVERY COLUMN THIS FORM MAY WRITE. `basis`, `interval_months`, `anchor_date` and `item_id`
  # joined the list for §8's suggestion panel: a proposed dated bill is "$85 every month, next due
  # Sep 21, paying the Phone item", and none of those four is derivable from the amount.
  #
  # Each carries a validation consequence — `shape_must_be_valid` on the first three,
  # `item_must_belong_to_pool` and `item_must_not_be_claimed` on the last — so shape is answered by
  # `Budget` and only OWNERSHIP is answered below.
  #
  # `category_id` AND `prorated` LEFT THE LIST WITH THE CATEGORY-MODE CAP (plan 3, task 3). Neither
  # column can be written any more — a rule is owned by a pool, and the daily ramp `prorated` fed
  # is deleted — and an unpermitted key is the only spelling of that which a tampered POST also
  # obeys.
  BUDGET_FIELDS = [:amount, :pool_id, :basis, :interval_months, :anchor_date, :item_id].freeze

  # GET /budgets/new
  #
  # PREFILLED FROM THE QUERY STRING when the suggestion panel sent the user here, and the prefill
  # goes through the same ownership scoping the POST does — a stranger's `item_id` in a GET would
  # render THEIR item's name on this user's form, which is the read-shaped half of the same leak.
  def new
    @budget = Budget.new
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
      redirect_to budget_page_path, notice: "Budget was successfully created."
    else
      render :new, status: :unprocessable_content
    end
  end

  # PATCH/PUT /budgets/1
  def update
    if @budget.update(budget_params)
      redirect_to budget_page_path, notice: "Budget was successfully updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  # DELETE /budgets/1
  def destroy
    @budget.destroy
    redirect_to budget_page_path, notice: "Budget was successfully deleted."
  end

  private

  # `Budget.for_user`, not a bare `Budget` — a scoped lookup, so another user's rule raises
  # RecordNotFound. It used to be contrasted with `current_user.budgets`, the association that
  # walked the category link; that association is deleted with the cap it reached.
  def set_budget
    @budget = Budget.for_user(current_user).find(params[:id])
  end

  # THE WRITE SIDE OF OWNERSHIP, and it has to be asked here because nothing else asks it.
  # `pool_id` is a wire parameter, and `Budget` cannot object to a foreign pool — it validates
  # that a pool is not an account, that the shape is legal and that the item belongs to it, never
  # WHOSE it is. Unscoped, `POST /budgets` with a stranger's pool id wrote a funding rule onto
  # their envelope and `PATCH` re-parented one of mine onto theirs; both then rendered on their
  # page. A scoped read beside an unscoped write is ownership on the way in only.
  #
  # WHERE THE LINE SITS, deliberately: `current_user.pools` and nothing more. Ownership is the
  # controller's question, while "not an account", "the right shape" and "the item belongs to this
  # pool" are Budget's own validations. Scoping to `.budget_pools` here would turn a user naming
  # their OWN account into a 404 — their record vanishing — where the model gives a legible 422.
  #
  # `category_id` USED TO BE SCOPED HERE TOO and is no longer permitted at all: a rule owned by a
  # category is not a shape this app can hold, so the key is refused rather than laundered. The
  # ownership pair that pinned it is retired with it (see the task report); the `pool_id` pair
  # below, which asks the same question of the owner that remains, stands.
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
    permitted = scoped_owner(permitted, :pool_id, current_user.pools)
    scoped_owner(permitted, :item_id, current_user.items)
  end

  # THE OPTIONAL ENVELOPE HALF (amendment A): the pool a proposing suggestion would create and the
  # category it would re-point at it. Present only when the panel sent one — every other request
  # to this controller leaves `@envelope` nil and `BudgetProposal` degrades to `budget.save`.
  #
  # `envelope[category_id]` RATHER THAN A TOP-LEVEL `category_id`, and the nesting is kept now that
  # the collision it was invented for is gone. `category_id` used to name the OWNER of a
  # category-mode cap on this same form while the engine's payload meant the category to be MOVED
  # into the new envelope — one key with two meanings, a request that quietly capped a category
  # when it was asked to fund an envelope. The cap is deleted and the top-level key is no longer
  # permitted at all, so the nesting now buys something narrower and still worth having: this id is
  # not a `Budget` column, and a payload that spelled it like one would invite the next reader to
  # add it back to BUDGET_FIELDS.
  #
  # KEYED ON THE CATEGORY, not on the presence of the `envelope` key: without a category there is
  # nothing to re-point, so there is no envelope half — and the rule then has no owner at all,
  # which `Budget#must_belong_to_a_pool` answers with a legible 422 rather than this raising.
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
  # gives. Skipped when blank, because a blank owner is an owner-less create re-rendering, which
  # Budget already answers (#must_belong_to_a_pool), and which is not a stranger's id.
  def scoped_owner(permitted, key, scope)
    return permitted if permitted[key].blank?

    permitted.merge(key => scope.find(permitted[key]).id)
  end
end
