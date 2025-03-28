# frozen_string_literal: true

class BudgetsController < ApplicationController
  before_action :set_budget, only: [:show, :edit, :update, :destroy]
  before_action :set_category, only: [:new, :create]

  # GET /budgets
  def index
    @budgets = current_user.budgets.includes(:category)
  end

  # GET /budgets/1
  def show; end

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
      redirect_to budgets_path, notice: "Budget was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /budgets/1
  def update
    if @budget.update(budget_params)
      redirect_to budgets_path, notice: "Budget was successfully updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /budgets/1
  def destroy
    @budget.destroy
    redirect_to budgets_path, notice: "Budget was successfully deleted."
  end

  private

  def set_budget
    @budget = current_user.budgets.find(params[:id])
  end

  def set_category
    @category = current_user.categories.expenses.find(params[:category_id]) if params[:category_id]
  end

  def budget_params
    params.require(:budget).permit(:amount, :period, :category_id)
  end
end
