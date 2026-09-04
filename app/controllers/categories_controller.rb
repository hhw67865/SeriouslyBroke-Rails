# frozen_string_literal: true

class CategoriesController < ApplicationController
  include Searchable
  include PeriodContext

  before_action :set_category, only: [:show, :edit, :update, :destroy, :toggle_tracked]
  before_action :set_categories, only: [:index]

  helper_method :claim_ledger

  # GET /categories
  def index
    # Categories are filtered in the get_categories before_action
  end

  # GET /categories/1
  #
  # THE HOLDINGS CARD, AND IT IS ONE CARD WHERE THERE WERE TWO (Task 7). `@budget_block` and
  # `@pool_card` both described the POOL behind a category — one in the row vocabulary, one with a
  # progress bar — and under the two-ledger model there is no pool behind a category at all: the
  # category holds the money (spec §3). Both are replaced by `_holdings_card`, built off the same
  # presenter, and the two-cards-one-envelope drift they spent three review rounds converging is
  # structurally gone.
  #
  # EXPENSE ONLY, and now that is the model's own line rather than a choice this action makes:
  # `Category#holder?` is `expense? && funded_since.present?`, so an INCOME category cannot hold
  # money and there is nothing for the card to say about one. Nil for the others, and the view
  # renders nothing for a nil.
  def show
    @holdings_card = CategoryBudgetPresenter.new(category: @category) if @category.expense?
  end

  # GET /categories/new
  #
  # NOTHING IS DEFAULTED ANY MORE. This built `categories.new(pool: current_user.default_account)`
  # because `pool_id` was required and a blank picker made every create a 422; the picker is gone
  # with the pool layer (two-ledger spec §5), and the three columns that replaced it —
  # `target_amount`, `priority`, `funded_since` — are all legitimately blank on an ordinary new
  # category. A category that holds nothing is the honest default: its spending drains available
  # until the user gives it a rule or an allocation, which is exactly what §4 says.
  #
  # `?type=` IS CHECKED AGAINST THE ENUM (plan 3, task 5), and this arm is a 500 rather than a
  # wrong heading: assigning an enum value the mapping does not hold raises ArgumentError, so
  # `/categories/new?type=savings` — a bookmark, a browser history entry, a link in an old email —
  # took the whole page down. `#known_type` is the same check `#set_categories` runs; an
  # unrecognised type simply selects nothing, which is what this form does with no `type` at all.
  #
  # THE FORM OPENS WITH BOTH RADIO SETS ANSWERED (design review H2/H3). It used to open with
  # neither: no type tile checked and no colour swatch ringed, which made two questions look
  # optional and produced two separate failure modes — a 422 saying "Category type can't be blank"
  # over a card the user had read as decorative, and a `color: ""` that painted the saved
  # category's chip as a transparent hole.
  #
  # EXPENSE, because it is what four in five categories are and it is the tab the New button is
  # pressed from; the brand sage, because that is what an uncoloured category has always been
  # painted (`Category::DEFAULT_COLOR`) — so the default is the truth the rest of the app was
  # already telling, now stated on the form where it can be changed.
  #
  # `#create` DOES NOT INHERIT THIS, deliberately: it builds from `category_params`, so a blank
  # type submitted by a tampered or scripted request still fails its presence validation. The
  # default is an affordance, not a second writer.
  def new
    @category = current_user.categories.new(
      category_type: known_type(params[:type]) || :expense,
      color: Category::DEFAULT_COLOR
    )
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

  def set_category
    @category = current_user.categories.find(params[:id])

    # Preload entries with their items for the recent activity section
    @recent_entries = @category.entries.includes(:item).order(date: :desc).limit(5)
  end

  # `pool_id` IS OUT AND THE THREE HOLDING COLUMNS ARE IN (two-ledger spec §3/§4, Task 7).
  #
  # WHAT THE REMOVAL BUYS. `pool_id` was permitted here through a `current_user.pools.find` because
  # an unscoped write put THIS user's whole spending history into a STRANGER's pool balance —
  # `PoolBalanceLedger::ENTRY_POOL_ID` joined on pool id with no user filter. Nothing reads
  # `categories.pool_id` any more (the ledger is `CategoryLedger` and it joins on the category's own
  # user), so the parameter is not narrowed, it is gone: the whole IDOR class it guarded against
  # cannot be expressed through this form.
  #
  # THE THREE THAT ARRIVE ARE ALL PLAIN COLUMNS OF THE RECORD ITSELF, so none of them needs an
  # ownership check — there is no foreign id to point at somebody else's row. Each is validated by
  # `Category#holding_columns_are_sane` (a target must be positive, a priority a non-negative
  # integer, and only an expense category may carry any of them), so a bad value is a legible 422
  # on the form that submitted it rather than a silent write.
  #
  # `funded_since` IS USER-EDITABLE, WHICH SPEC §4 REQUIRES AND WHICH MOVES MONEY. It is the day a
  # category starts counting its own spending; earlier spending drains available. Editing it
  # therefore RE-READS history in both directions, and it moves the category in and out of
  # `Category.in_fill_order` — clearing it on a rule-bearing category drops it out of the
  # distribution waterfall and onto the Budget page's "Not in the fill order" band. The form says
  # both things beside the field; this is where the value is allowed in.
  def category_params
    params.expect(category: [:name, :category_type, :color, :target_amount, :priority, :funded_since])
  end

  # THE ONE CHECK BOTH `?type=` READERS RUN. A type the enum does not hold is a stale bookmark now
  # — `savings` left the mapping in plan 3 task 5 — and it broke two screens in two different ways:
  # here it reached `Category.with_type`'s three-armed case, came back NIL and 500ed inside
  # `apply_search`, and in `#new` it raised ArgumentError on assignment. nil for anything unknown,
  # and each caller says what it does with that.
  def known_type(type) = Category.category_types.key?(type) ? type : nil

  # Anything unrecognised lands on expenses — the page's own default — rather than heading a list
  # of expenses "Savings Categories", which is what would happen if only the scope were made total
  # and `@type` were left as typed.
  def set_categories
    @type = known_type(params[:type]) || "expense"
    @search_state = current_search_state(params)
    @query = @search_state[:query] # For backward compatibility

    categories = current_user.categories.with_type(@type)

    # Apply search using the new searchable system
    categories = apply_search(categories, { q: params[:q], field: params[:field] })

    @categories = categories.order(name: :asc).to_a
  end

  # ** ONE LEDGER FOR THE WHOLE INDEX (fix round 1, MED-3 — re-homed on claims). **
  #
  # THE CARD PRINTS WHAT ITS CATEGORY'S MONEY IS, and the unbatched door (`Category#claim`) costs a
  # spending query and an adjustment query PER RULE — on the one screen in this app that renders
  # every category a user owns. `ClaimLedger` is the batched door and it is the same shape this
  # method had under `CategoryLedger`: build ONE, let the view ask it per category, and the grouped
  # queries run once whatever the row count. Home and the Budget page already do exactly this.
  #
  # THE WHOLE USER RATHER THAN THE FILTERED SET, and that is a change from the `CategoryLedger`
  # version. `ClaimLedger` is built over every rule its user owns — `#total_claims` and `#free` are
  # figures about the user, not about a page's selection — so handing it a filtered list would be
  # handing it a set it does not take. A category outside the filter simply is never asked about.
  #
  # A HELPER METHOD RATHER THAN AN IVAR SET IN `#index`, so the SHOW action and the card partial can
  # reach the same reader without a second construction path, and so an index of income categories —
  # none of which carries a rule — pays for nothing: `ClaimLedger` memoises each grouped query at
  # its FIRST read, and a page that asks no claim runs no query.
  def claim_ledger
    @claim_ledger ||= ClaimLedger.new(current_user, today: current_user.today)
  end
end
