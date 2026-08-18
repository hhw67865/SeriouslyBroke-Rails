# frozen_string_literal: true

class CategoriesController < ApplicationController
  include Searchable
  include PeriodContext

  before_action :set_category, only: [:show, :edit, :update, :destroy, :toggle_tracked]
  before_action :set_categories, only: [:index]

  # GET /categories
  def index
    # Categories are filtered in the get_categories before_action
  end

  # GET /categories/1
  #
  # The budget block is spec §8.1's, and it is built for EXPENSE categories only because that is
  # the only kind whose pool answers a question about a budget — an income category names the
  # account its money lands in, which is not a state the block has words for. Nil for the others,
  # and the view renders nothing for a nil.
  # THE POOL CARD GETS THE SAME OBJECT, and one instance serves both blocks (2d task 6). The card
  # is older than the budget block and rendered savings chrome for every pool it was given — an
  # ACCOUNT read "Savings Pool / Target: $1,000.00 / -30% complete", a savings progress bar drawn
  # on a buffer — so it now asks what its pool IS, which is exactly the question this presenter
  # already answers for the block above it.
  #
  # It is built for every pooled category, not just `expense?` ones: a SAVINGS category points at a
  # pool too, and that is the arm whose rendering does not change. Memoised, so an expense category
  # pointing at an envelope builds ONE PoolStatus for both blocks rather than two that could
  # disagree about the same envelope on the same page.
  def show
    @budget_block = category_pool_presenter if @category.expense?
    @pool_card = category_pool_presenter if @category.pool.present?
  end

  # GET /categories/new
  # THE POOL DEFAULTS TO THE USER'S DEFAULT ACCOUNT (plan 3 decision 3). `categories.pool_id` is
  # required now, and a form that opened with nothing selected would make every new category a
  # 422 the user has to read before they can guess what the field wants. The default is also the
  # right answer for most new categories: an account IS the buffer (§7.1), so "this comes out of my
  # buffer" is what spending means before it has an envelope, and it is the shape the Budget page's
  # rate detector then offers to give one to.
  #
  # `default_account` is nullable on `users`, so this can still leave the field unset — the form
  # then opens on the first pool in the list and the validation is what refuses a genuine blank.
  def new
    @category = current_user.categories.new(pool: current_user.default_account)
    @category.category_type = params[:type] if params[:type].present?
  end

  # GET /categories/1/edit
  def edit; end

  # POST /categories
  def create
    @category = current_user.categories.new(category_params)

    if @category.save
      redirect_to categories_path(type: @category.category_type), notice: "Category was successfully created."
    else
      render :new, status: :unprocessable_content
    end
  end

  # PATCH/PUT /categories/1
  def update
    if @category.update(category_params)
      redirect_to categories_path(type: @category.category_type), notice: "Category was successfully updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  # DELETE /categories/1
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

  def category_pool_presenter
    @category_pool_presenter ||= CategoryBudgetPresenter.new(category: @category)
  end

  def set_category
    @category = current_user.categories.find(params[:id])

    # Preload entries with their items for the recent activity section
    @recent_entries = @category.entries.includes(:item).order(date: :desc).limit(5)
  end

  # §7a'S WIDENED-PARAMETER CLASS, FOURTH APPEARANCE — and the widening is decision 3's. `pool_id`
  # has been permitted here for a long time, but it was a corner of the form nothing routinely
  # wrote; requiring a pool on every category made it the ORDINARY payload of every create and
  # every update, which is exactly when an unscoped write starts to matter.
  #
  # WHAT IT COSTS UNSCOPED, and it is the invariant rather than a leak of one screen.
  # `PoolBalanceLedger::ENTRY_POOL_ID` resolves an entry through
  # `COALESCE(entries.pool_id, categories.pool_id)` and joins on pool id with NO user filter — so a
  # stranger's `pool_id` here puts THIS user's whole spending history into THAT user's pool balance,
  # and `Σ pools == your bank balance` becomes false for both of them at once. `categories#show`
  # then renders the stranger's pool name, noun and status back to this user.
  #
  # `find` through `current_user.pools`, so a stranger's id raises RecordNotFound and arrives as the
  # same 404 `#set_category` gives — the identical shape `BudgetsController#scoped_owner` uses two
  # files away, for the identical reason.
  #
  # WHERE THE LINE SITS, deliberately: ownership here, SHAPE in the model. A user naming one of
  # their OWN budget pools on an income category is `Category#income_must_land_in_an_account`'s
  # legible 422, not a 404 — scoping to `.accounts` here would make the user's own record vanish
  # instead. Both directions are pinned in spec/requests/categories_spec.rb.
  #
  # Skipped when blank, because a blank pool is the owner-less create re-rendering, which the
  # required `belongs_to :pool` already answers, and which is not a stranger's id.
  def category_params
    permitted = params.expect(category: [:name, :category_type, :color, :pool_id])
    return permitted if permitted[:pool_id].blank?

    permitted.merge(pool_id: current_user.pools.find(permitted[:pool_id]).id)
  end

  def set_categories
    @type = params[:type] || "expense"
    @search_state = current_search_state(params)
    @query = @search_state[:query] # For backward compatibility

    categories = current_user.categories.with_type(@type)

    # Apply search using the new searchable system
    categories = apply_search(categories, { q: params[:q], field: params[:field] })

    @categories = categories.order(name: :asc)
  end
end
