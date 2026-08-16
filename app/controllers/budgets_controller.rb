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
  # #destroy takes the path BEFORE the delete, and that ordering is DEFENSIVE, NOT LOAD-BEARING
  # — an earlier version of this comment claimed otherwise and was wrong. Measured: a destroyed
  # Budget is frozen but keeps its `category_id`/`pool_id`, and the owner row is not touched by
  # the child's delete, so `owner_path` resolves to the same URL after the destroy as before it.
  # Taking it first states that the destination is a fact about the rule as it stood, and it
  # survives a future `dependent:` or callback that does start clearing the link — but nothing
  # today depends on the order, and no example fails if it is reversed.
  def owner_path(budget)
    budget.category ? category_path(budget.category) : pool_path(budget.pool)
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
  # `find`, so a stranger's id raises RecordNotFound and arrives as the same 404 #set_budget
  # gives. Skipped when blank, because a blank category is the pool-mode edit form submitting
  # its empty picker and an owner-less create re-rendering — both of which Budget already
  # answers (#exactly_one_owner), and neither of which is a stranger's id.
  #
  # `pool_id` is deliberately absent from the permitted list, so pool-mode is not writable
  # through this controller at all and the identical hole cannot exist on the other owner.
  # Two request examples pin that, so widening the list later cannot reopen it unwatched.
  def budget_params
    permitted = params.expect(budget: [:amount, :category_id, :prorated])
    return permitted if permitted[:category_id].blank?

    permitted.merge(category_id: current_user.categories.find(permitted[:category_id]).id)
  end
end
