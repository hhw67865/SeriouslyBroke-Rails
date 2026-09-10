# frozen_string_literal: true

class CategoriesController < ApplicationController
  include Searchable
  include PeriodContext

  before_action :set_category, only: [:show, :edit, :update, :destroy, :toggle_tracked]
  before_action :set_categories, only: [:index]

  helper_method :claim_ledger, :claim_rows

  def index; end

  def show
    @holdings_card = CategoryBudgetPresenter.new(category: @category, claims: claim_ledger, rows: claim_rows) if @category.expense?
  end

  def new
    @category = current_user.categories.new(category_type: known_type(params[:type]) || :expense, color: Category::DEFAULT_COLOR)
  end

  def edit; end

  def create
    @category = current_user.categories.new(category_params)
    if @category.save
      redirect_to categories_path(type: @category.category_type), notice: "Category was successfully created."
    else
      render :new, status: :unprocessable_content
    end
  end

  def update
    if @category.update(category_params)
      redirect_to categories_path(type: @category.category_type), notice: "Category was successfully updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    category_type = @category.category_type
    @category.destroy
    redirect_to categories_path(type: category_type), notice: "Category was successfully deleted."
  end

  def toggle_tracked
    if @category.update(tracked: !@category.tracked?)
      redirect_back_or_to(reports_path)
    else
      redirect_back_or_to(reports_path, alert: "Could not update category.")
    end
  end

  def update_tracked
    params[:categories]&.each do |id, attrs|
      current_user.categories.find_by(id: id)&.update(tracked: attrs[:tracked] == "1")
    end
    redirect_back_or_to(reports_path)
  end

  private

  def set_category
    @category = current_user.categories.find(params[:id])
    @recent_entries = @category.entries.includes(:item).order(date: :desc).limit(5)
  end

  def category_params = params.expect(category: [:name, :category_type, :color, :priority, :regular])

  def known_type(type) = Category.category_types.key?(type) ? type : nil

  def set_categories
    @type = known_type(params[:type]) || "expense"
    @search_state = current_search_state(params)
    categories = current_user.categories.with_type(@type)
    categories = apply_search(categories, { q: params[:q], field: params[:field] })
    @categories = categories.order(name: :asc).to_a
  end

  def claim_rows = @claim_rows ||= ClaimRows.new(ledger: claim_ledger, today: current_user.today)
  def claim_ledger = @claim_ledger ||= ClaimLedger.new(current_user, today: current_user.today)
end
