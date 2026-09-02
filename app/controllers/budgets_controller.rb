# frozen_string_literal: true

class BudgetsController < ApplicationController
  before_action :set_budget, only: [:edit, :update, :destroy]

  # EVERY COLUMN THIS FORM MAY WRITE. `basis`, `interval_months`, `anchor_date` and `item_id`
  # joined the list for §8's suggestion panel: a proposed dated bill is "$85 every month, next due
  # Sep 21, paying the Phone item", and none of those four is derivable from the amount.
  #
  # Each carries a validation consequence — `shape_must_be_valid` on the first three,
  # `item_must_belong_to_category` and `item_must_not_be_claimed` on the last — so shape is answered
  # by `Budget` and only OWNERSHIP is answered below.
  #
  # `pool_id` LEFT THE LIST AND `category_id` TOOK ITS PLACE (two-ledger spec §3). A rule belongs to
  # the thing that holds the money, and `category_id` is not the cap-era key of the same name: that
  # one named a category a rule CAPPED while a pool funded it, and the collision it caused is what
  # made the accept flow nest its own `envelope[category_id]`. There is one owner and one key for
  # it now. `pool_id` is refused rather than laundered — an unpermitted key is the only spelling of
  # "this column is not writable" that a tampered POST also obeys — and Task 8 drops the column.
  #
  # `prorated` LEFT WITH THE CAP (plan 3, task 3) and has not come back: the daily ramp it fed is
  # deleted.
  BUDGET_FIELDS = [:amount, :category_id, :basis, :interval_months, :anchor_date, :item_id].freeze

  # GET /budgets/new
  #
  # PREFILLED FROM THE QUERY STRING when the suggestion panel sent the user here, and the prefill
  # goes through the same ownership scoping the POST does — a stranger's `item_id` in a GET would
  # render THEIR item's name on this user's form, which is the read-shaped half of the same leak.
  # A BARE `/budgets/new` IS A HAND-MADE RULE (Henry's ruling of 2026-08-20), and it opens as a
  # PER-PERIOD RATE. `basis` defaults to `monthly` on the column, which with no interval and no
  # anchor is the one combination `Budget#shape_must_be_valid` refuses outright — so a form that
  # asked only for the category and the amount could never save. `per_period` is §3.1's row 1: no
  # interval, no anchor, valid on its own, and the shape a user typing a rule from scratch means.
  #
  # ASSIGNED BEFORE THE PREFILL, never after: a proposal states its own `basis` and must overwrite
  # this rather than be overwritten by it.
  def new
    @budget = Budget.new(basis: :per_period)
    @budget.assign_attributes(prefill_attributes)
    @owner_picker = prefill_attributes[:category_id].blank?
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
  # ONE FORM AND ONE POST for the whole accept flow. What accepting makes happen — the
  # `funded_since` stamp beside the rule — is `BudgetProposal`'s to explain and this action does not
  # restate it; here it is only that both outcomes render the same two branches they always did.
  def create
    @budget = Budget.new(budget_params)

    if BudgetProposal.new(budget: @budget).save
      redirect_to budget_page_path, notice: "Budget was successfully created."
    else
      # THE PICKER SURVIVES A REFUSAL, AND ON EVERY PATH. `@budget.category_id` is now whatever the
      # request carried, so it cannot answer "was this form asking for an owner" the way it can on
      # the GET — and the honest answer for a refused create is that it may as well be. A suggestion
      # accept that fails validation (an item already claimed) comes back with the picker
      # preselected to the category the panel named rather than its name in a grey box: a form that
      # still says the right owner and now lets it be changed, on a screen the user has just been
      # refused by. The owner-less create — a bare `/budgets/new` submitted with nothing chosen —
      # needs the picker outright, since it is the control the refusal is about.
      @owner_picker = true
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
  # RecordNotFound. It spans both owner lanes until Task 8, which is what keeps a rule written
  # before the cutover reachable by its own Edit link.
  def set_budget
    @budget = Budget.for_user(current_user).find(params[:id])
  end

  # THE WRITE SIDE OF OWNERSHIP, and it has to be asked here because nothing else asks it.
  # `category_id` is a wire parameter, and `Budget` cannot object to a foreign category — it
  # validates that the shape is legal and that the item belongs to the category, never WHOSE it is.
  # Unscoped, `POST /budgets` with a stranger's category id wrote a funding rule onto their
  # envelope and `PATCH` re-parented one of mine onto theirs; both then rendered on their page. A
  # scoped read beside an unscoped write is ownership on the way in only.
  #
  # WHERE THE LINE SITS, deliberately: `current_user.categories` and nothing more. Ownership is the
  # controller's question, while "the right shape" and "the item belongs to this category" are
  # Budget's own validations. Scoping to `.expenses` here would turn a user naming their OWN income
  # category into a 404 — their record vanishing — where the model gives a legible 422.
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

  # `item_id` IS §7a'S CLASS AGAIN, AND IT IS THE SHARPEST OF THEM. A rule names the item it pays;
  # `Budget` validates that the item sits in the rule's category, never WHOSE item it is. Unscoped,
  # `POST /budgets` with a stranger's item id writes a funding rule against THEIR spending — the
  # rule then reads their entries through `BudgetCalculator#paid_since_anchor` and reports their
  # bills as paid or unpaid on this user's page. `current_user.items` walks the user's categories,
  # so a stranger's id is not found.
  #
  # The line stays exactly where Task 2 drew it: whose, here; what shape, in the model. An item of
  # the user's OWN in the wrong category is `item_must_belong_to_category`'s 422, not a 404.
  def scoped_owners(permitted)
    permitted = scoped_owner(permitted, :category_id, current_user.categories)
    scoped_owner(permitted, :item_id, current_user.items)
  end

  # `find`, so a stranger's id raises RecordNotFound and arrives as the same 404 #set_budget
  # gives. Skipped when blank, because a blank owner is an owner-less create re-rendering, which
  # Budget already answers (#must_have_an_owner), and which is not a stranger's id.
  def scoped_owner(permitted, key, scope)
    return permitted if permitted[key].blank?

    permitted.merge(key => scope.find(permitted[key]).id)
  end
end
