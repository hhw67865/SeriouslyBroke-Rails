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
  # Taken BEFORE the destroy in #destroy, because the record's associations are the only
  # thing that knows where to go back to and the delete is what takes them away.
  def owner_path(budget)
    budget.category ? category_path(budget.category) : pool_path(budget.pool)
  end

  def set_category
    @category = current_user.categories.expenses.budgetable.find(params[:category_id]) if params[:category_id]
  end

  def budget_params
    params.expect(budget: [:amount, :category_id, :prorated])
  end
end
