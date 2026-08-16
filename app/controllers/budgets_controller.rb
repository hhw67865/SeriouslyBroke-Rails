# frozen_string_literal: true

class BudgetsController < ApplicationController
  before_action :set_budget, only: [:edit, :update, :destroy]
  before_action :set_category, only: [:new, :create]

  # GET /budgets/new
  def new
    @budget = @category ? @category.build_budget : Budget.new
  end

  # GET /budgets/1/edit
  def edit; end

  # POST /budgets
  def create
    @budget = Budget.new(budget_params)

    if @budget.save
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
  def budget_params
    permitted = params.expect(budget: [:amount, :category_id, :pool_id, :prorated])
    permitted = scoped_owner(permitted, :category_id, current_user.categories)
    scoped_owner(permitted, :pool_id, current_user.pools)
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
