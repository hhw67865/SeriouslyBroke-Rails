# frozen_string_literal: true

class BudgetsController < ApplicationController
  before_action :set_budget, only: [:edit, :update, :destroy]

  # ** EVERY FIELD THIS FORM MAY SUBMIT, AND THEY ARE THE USER'S WORDS RATHER THAN THE COLUMNS
  # (two-shapes spec §5; rules-own-the-budget §4). ** `basis` is not on the list; `schedule`
  # (`per_period` / `by_date`) and `repeats` are, beside the one column a person is asked about
  # directly (`rule_type`).
  #
  # ** `unspent` AND `target-amount` LEFT WITH THE COLUMNS (two-shapes §7), AND THE KEYS ARE DROPPED
  # RATHER THAN IGNORED. ** An unpermitted key is the only spelling of "this is not writable" that a
  # hand-made POST also obeys, which is the same reasoning `pool_id` and `prorated` left under.
  #
  # The wire used to carry `basis`, `interval_months` and `anchor_date` raw, which made every caller
  # a second author of §2.1's table — and the form could reach only two of its seven rows. The
  # mapping is `RuleForm`'s, spelled once and in both directions, so what a submission carries is
  # what the screen asked.
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
  BUDGET_FIELDS = [
    :category_id,
    :item_id,
    :rule_type,
    :amount,
    :schedule,
    :repeats,
    :interval_months,
    :anchor_date
  ].freeze

  # GET /budgets/new
  #
  # PREFILLED FROM THE QUERY STRING when the suggestion panel sent the user here, and the prefill
  # goes through the same ownership scoping the POST does — a stranger's `item_id` in a GET would
  # render THEIR item's name on this user's form, which is the read-shaped half of the same leak.
  #
  # A BARE `/budgets/new` IS A HAND-MADE RULE (Henry's ruling of 2026-08-20), and it opens as a
  # PER-PERIOD RATE THAT RESETS — `RuleForm::DEFAULT_SCHEDULE`, not a `basis:` assigned here. The
  # column's own default is `monthly`, which with no interval and no anchor is the one combination
  # `Budget#shape_must_be_valid` refuses outright, so the default has to be stated somewhere; it is
  # stated once, on the class that owns the mapping, and a proposal's own `schedule` simply
  # overwrites it.
  def new
    @rule_form = RuleForm.new(current_user, prefill_attributes)
    @owner_picker = prefill_attributes[:category_id].blank?
  end

  # GET /budgets/1/edit
  #
  # THE WHOLE RULE, READ BACK AS THE WORDS THAT WROTE IT (`RuleForm.from`). Every control §4 lists
  # renders on this path except the category, and a shape change here is legal: the claim is
  # computed, so the walk re-runs from the rule's accrual start under whatever shape is saved.
  #
  # ** THE PREFILL ON THIS PATH IS THE AMOUNT AND NOTHING ELSE (fix round 1 — M1). ** A drift
  # suggestion is the only thing that links here with a payload, and the only thing it has to say is
  # a figure it MEASURED; the rest of the rule is already on the row. Merging the whole query string
  # over `RuleForm.from` handed a GET the power to re-word an existing rule, and two of those
  # re-wordings were live:
  #
  #   `?budget[category_id]=<another of my categories>` rendered the read-only box with the OTHER
  #     category's name, and the hidden field carried it — so Save RE-PARENTED the rule, from a
  #     link, with the form showing the destination as if it were the rule's own owner.
  #   `?budget[schedule]=per_period` on a dated bill server-rendered the date block hidden with the
  #     date still in it (`toggle()` early-returns when the state already matches), and Save was
  #     then refused for a due date on a control that was not on screen.
  #
  # Both are shapes the user never chose, arriving as a URL. The amount survives because the figure
  # is in THE RULE'S OWN UNIT — `SuggestionEngine#rule_unit_amount` inverts `Budget#steady_ask`
  # before putting it on the wire, precisely so nothing downstream converts — and because it is the
  # one field the panel has a measurement for. Nothing is written: the user still has to submit.
  def edit
    @current_amount = @budget.amount
    words = RuleForm.from(@budget).merge(prefill_attributes.slice(:amount))
    @rule_form = RuleForm.new(current_user, words, budget: @budget)
  end

  # POST /budgets
  #
  # ONE FORM AND ONE POST for the whole accept flow. What accepting makes happen — the
  # `funded_since` stamp beside the rule — is `BudgetProposal`'s to explain and this action does not
  # restate it; `RuleForm#save` is the one door onto both writes.
  def create
    @rule_form = RuleForm.new(current_user, budget_params)

    if @rule_form.save
      redirect_to budget_page_path, notice: "Budget was successfully created."
    else
      # THE PICKER SURVIVES A REFUSAL, AND ON EVERY PATH. `category_id` is now whatever the
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
  #
  # THE SAME DOOR AS `#create`, on a rule that already exists. `RuleForm#save` writes it plainly —
  # no `funded_since` stamp, because the category is already holding and re-stamping it would move
  # the date every time somebody corrected an amount.
  #
  # ** OVER THE RULE'S OWN WORDS, NOT OVER THE FORM'S DEFAULTS. ** `RuleForm` reads a schedule of
  # `per_period` when nothing says otherwise, which is right for a blank form and catastrophic for a
  # PATCH: a request naming only an amount would silently strip a six-monthly bill of its interval
  # and its due date. §4's form submits every control on every save, so the merge changes nothing
  # about what a user's own submission does — a field they CLEARED arrives as a blank and still
  # clears — and it makes a partial write mean what it says.
  #
  # ** `category_id` IS NOT WRITABLE HERE AT ALL (fix round 1 — M1). ** §4: the category is READ-ONLY
  # on an edit, and the form no longer submits it — the rule already has an owner and the page that
  # LISTS rules is where moving one between categories belongs. It used to be permitted and merely
  # ownership-scoped, which made a re-parent a legal PATCH that no control on the form could ask for;
  # an unpermitted key is the only spelling of "this is not writable" that a hand-made request also
  # obeys. `Budget#category_must_be_an_expense` stays where it is: a category the user later switches
  # to income can still refuse a save from this action.
  def update
    words = RuleForm.from(@budget).merge(update_params.to_h.symbolize_keys)
    @rule_form = RuleForm.new(current_user, words, budget: @budget)

    if @rule_form.save
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
  # RecordNotFound. ONE LANE since Task 8: the scope is `where(category_id: user.categories
  # .select(:id))` and `budgets.category_id` is NOT NULL, so a rule's owner is its category and
  # ownership is that category's owner. The `.or` over `pool_id` it used to carry — the arm that kept
  # a pre-cutover rule reachable by its own Edit link — died with the column.
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

  # ** THE SAME LIST WITHOUT THE OWNER, WHICH IS THE WHOLE OF `#update`'s WRITABLE SURFACE. ** The
  # category is chosen once, when the rule is created, and §4 makes it read-only afterwards; the key
  # is dropped rather than scoped, so a hand-made PATCH is the same no-op the form is. `item_id` is
  # still here and still scoped: which item a rule pays IS editable, and it is the sharper of the two
  # ids besides.
  def update_params = scoped_owners(params.expect(budget: BUDGET_FIELDS - [:category_id]))

  # THE SAME LIST AND THE SAME SCOPING, read off a GET. `expect` raises ParameterMissing on a
  # bare `/budgets/new`, which is the ordinary way this form is reached, so the absence of the
  # key is an empty prefill rather than a 400.
  #
  # A PLAIN SYMBOL-KEYED HASH, because `#edit` MERGES it over `RuleForm.from` — the rule's own words
  # first, the suggestion's correction on top — and `Hash#merge` cannot take `Parameters`.
  # ** A BARE `?category_id=` IS THE CATEGORY PANEL'S OWN DOOR (two-shapes spec §4). ** "+ New rule
  # for Groceries" carries the category and nothing else — there is no measurement behind it, so
  # there is no `budget[…]` payload to nest it in — and without this the form opened with the owner
  # picker on it, offering to send the rule somewhere the button's own words did not promise.
  #
  # THE SAME SCOPING AS EVERY OTHER OWNER ON THIS CONTROLLER: it goes through
  # `current_user.categories`, so a stranger's id is a 404 rather than a rendered name. It is folded
  # UNDER the payload's own key, not over it — a suggestion's `budget[category_id]` is the measured
  # answer and a query parameter must not be able to redirect it.
  def prefill_attributes
    @prefill_attributes ||= begin
      from_query = { category_id: params[:category_id].presence }.compact
      scoped_owners(from_query.merge(payload)).to_h.symbolize_keys
    end
  end

  def payload = params[:budget].blank? ? {} : params.expect(budget: BUDGET_FIELDS).to_h.symbolize_keys

  # `item_id` IS §7a'S CLASS AGAIN, AND IT IS THE SHARPEST OF THEM. A rule names the item it pays;
  # `Budget` validates that the item sits in the rule's category, never WHOSE item it is. Unscoped,
  # `POST /budgets` with a stranger's item id writes a funding rule against THEIR spending — the
  # rule then reads their entries through `ClaimCalculator`'s own lane (`Entry.draining` narrowed to
  # the rule's item) and reports their bills as paid or unpaid on this user's page. `current_user.items` walks the user's categories,
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
