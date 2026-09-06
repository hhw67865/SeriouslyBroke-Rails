# frozen_string_literal: true

class BudgetsController < ApplicationController
  before_action :set_budget, only: [:edit, :update, :destroy]
  before_action :set_previewed_budget, only: [:preview]

  # ** WHY A BARE `/budgets/new` IS NOT A PAGE ANY MORE (two-shapes spec §5). ** The form is
  # `/budgets/new?category_id=`: every door into it — the category panel's "+ New rule for
  # Groceries" and a suggestion's "Write it →" — names the category the rule is for, and the page
  # itself is titled "New rule for Groceries" with the category's own items in its select and the
  # category's own suggestions above step 1. Without one there is no page to render: the picker that
  # used to stand in for it is deleted, because a select offering to send the rule somewhere the
  # button did not promise is the thing §4 moved this form onto a per-category door to end.
  #
  # THE ANSWER IS THE BUDGET PAGE, WHICH IS WHERE THE DOORS ARE, and a flash saying so — a 404 would
  # be a lie (the form exists) and a blank picker would be the control this task deleted.
  NEW_NEEDS_A_CATEGORY = "Open a category on the Budget page to write a rule for it."

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
  # ** `keeps` JOINED WITH THE FUND (two-shapes §12). ** It is `RuleForm`'s word for
  # `budgets.keeps_unspent`, which is not on this list for the same reason `basis` is not: the wire
  # carries what the screen asked, and the column is `RuleForm#schedule_columns`' answer.
  BUDGET_FIELDS = [
    :category_id,
    :item_id,
    :rule_type,
    :amount,
    :schedule,
    :repeats,
    :keeps,
    :interval_months,
    :anchor_date
  ].freeze

  # GET /budgets/new
  #
  # PREFILLED FROM THE QUERY STRING when the suggestion panel sent the user here, and the prefill
  # goes through the same ownership scoping the POST does — a stranger's `item_id` in a GET would
  # render THEIR item's name on this user's form, which is the read-shaped half of the same leak.
  #
  # THE FORM OPENS AS A PER-PERIOD RATE THAT RESETS — `RuleForm::DEFAULT_SCHEDULE`, not a `basis:`
  # assigned here. The column's own default is `monthly`, which with no interval and no anchor is the
  # one combination `Budget#shape_must_be_valid` refuses outright, so the default has to be stated
  # somewhere; it is stated once, on the class that owns the mapping, and a proposal's own `schedule`
  # simply overwrites it.
  def new
    @rule_form = RuleForm.new(current_user, prefill_attributes)
    return redirect_to budget_page_path, alert: NEW_NEEDS_A_CATEGORY if category_in_force.blank?

    prepare_page
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
  # Both are shapes the user never chose, arriving as a URL. The amount survives because it is the
  # one field the panel has a measurement for, and because the figure and the box are in the SAME
  # unit: the engine measures per-period money and `RuleForm.from` shows per-period money on both
  # rate shapes (fix round 1's ruling), so nothing on either side converts. Nothing is written: the
  # user still has to submit.
  #
  # ** THE PREFILLED FIGURE IS NAMED AS SUCH (fix wave — MED-4). ** When a drift suggestion supplies
  # the amount, the box no longer holds what `RuleForm.from` put there — and on the one shape whose
  # read-back CONVERTS, the note under the box said "shown here as what it costs each period" about a
  # figure that had been replaced ($200.00 proposed over a $260.00-a-month rule that costs $120.00).
  # The note needs to know that the box is a proposal rather than the row, and this is where that
  # fact is: nowhere else can tell a prefill from a figure the user typed on a refused submit.
  def edit
    @current_amount = @budget.amount
    @suggested_amount = prefill_attributes[:amount]
    words = RuleForm.from(@budget, user: current_user).merge(prefill_attributes.slice(:amount))
    @rule_form = RuleForm.new(current_user, words, budget: @budget)
    prepare_page
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
      # ** THE REFUSED FORM COMES BACK ON THE CATEGORY IT WAS OPENED ON. ** The owner is read off the
      # record the words were applied to rather than off the query string, because on this path the
      # query string is empty — a submission carries `budget[category_id]` in the form's own hidden
      # field, already ownership-scoped by `#budget_params`. `#prepare_page` is nil-safe for the one
      # shape that has no owner at all (a hand-made POST), which `Budget#must_have_an_owner` answers
      # with a 422 the form prints in its base notification.
      prepare_page
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
    words = RuleForm.from(@budget, user: current_user).merge(update_params.to_h.symbolize_keys)
    @rule_form = RuleForm.new(current_user, words, budget: @budget)

    if @rule_form.save
      redirect_to budget_page_path, notice: "Budget was successfully updated."
    else
      prepare_page
      render :edit, status: :unprocessable_content
    end
  end

  # POST/PATCH /budgets/preview
  #
  # ** THE FORM'S STICKY CARD, SAID BY THE SERVER (two-shapes spec §5). ** It builds the rule the
  # blanks currently describe — UNSAVED, through the same `RuleForm` and the same ownership scoping
  # `#create` uses — and prices it with ONE `ClaimCalculator`, so the per-period figure on the card
  # is `ClaimCalculator#standing_ask` itself rather than a second arithmetic that could drift from
  # the page it links to. Nothing is written and nothing is validated: a half-filled form gets the
  # blanks it is missing (`RulePreview#missing`), never a 422.
  #
  # ** TWO RESPONSES, AND THE SECOND IS THE NO-JAVASCRIPT ONE. ** A Turbo frame request gets the
  # frame alone, which is what makes a refresh-per-keystroke cheap — the chips, the item select and
  # the suggestion engine behind them are not re-rendered. Anything else gets the WHOLE form page
  # with the card updated, which is what the "Preview" button does in a browser with no JavaScript
  # at all: the same act, one navigation instead of one frame.
  #
  # `?id=` IS THE RULE BEING EDITED, and `#set_previewed_budget` looks it up through
  # `Budget.for_user` — so a stranger's rule is the same 404 `#edit` gives, and the preview cannot
  # be used to read one. The words are merged over the rule's own (`RuleForm.from`) for exactly the
  # reason `#update` merges them: a submission naming only an amount must not silently re-shape a
  # six-monthly bill on the card.
  def preview
    @rule_form = RuleForm.new(current_user, preview_words, budget: @budget)
    @preview = RulePreview.new(@rule_form, user: current_user)

    return render partial: "budgets/preview", locals: { preview: @preview } if turbo_frame_request?

    prepare_page
    render @budget ? :edit : :new
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

  # THE SAME SCOPED LOOKUP FOR THE PREVIEW, whose rule rides as a query parameter rather than in the
  # path (the route is a collection one, because the rule being previewed may not exist yet). A
  # stranger's id is the same 404 every other member of this controller gives.
  #
  # THE AMOUNT IS READ BEFORE ANYTHING IS ASSIGNED, because `RuleForm` applies the submitted words
  # to this very record in its constructor — so a reader taken afterwards would be the SUBMITTED
  # figure wearing the label "Currently".
  def set_previewed_budget
    return if params[:id].blank?

    @budget = Budget.for_user(current_user).find(params[:id])
    @current_amount = @budget.amount
  end

  # ** WHAT EVERY RENDER OF THIS FORM NEEDS BESIDES THE FORM OBJECT (two-shapes spec §5). ** The
  # page is titled and breadcrumbed by its CATEGORY, its item select is that category's items, its
  # chips are that category's suggestions, and its right-hand column is the preview. All four are
  # set here so that `#new`, `#edit`, a refused `#create`/`#update` and the no-JavaScript `#preview`
  # render the same page rather than four subsets of it.
  #
  # `@preview` IS `||=` BECAUSE `#preview` HAS ALREADY BUILT ONE — one card, one calculator, whatever
  # brought the request in.
  def prepare_page
    @category = category_in_force
    @preview ||= RulePreview.new(@rule_form, user: current_user)
    @chips = chips_for(@category)
  end

  # THE OWNER, OFF THE RECORD THE WORDS HAVE BEEN APPLIED TO — never off the query string. On every
  # path that reaches this the id has already been through `#scoped_owners` (a GET's prefill, a
  # POST's payload) or off the row itself (`#set_budget`), so this is a read of an owner already
  # proven to be the user's rather than a second, weaker check.
  def category_in_force = @rule_form.budget.category

  # ** THE CHIPS ABOVE STEP 1 — THIS CATEGORY'S SUGGESTIONS, IN THE ENGINE'S OWN ORDER (§5). ** The
  # same rows the Budget page's open panel prints, rendered as fill-the-blanks chips: the engine has
  # already MEASURED a rule the user is here to write, so making them re-type it would be asking for
  # a figure the page is holding.
  #
  # ** ON AN EDIT, ONLY THE ONES ABOUT THIS RULE. ** A drift and a dead-rule suggestion name a
  # `Budget` as their subject; a dated bill names an Item and a rate names the Category, and neither
  # is about the rule on screen — offering "Water — $48.20 every 2 months" on the Electric rule's
  # edit form would be a chip that silently re-points what the user opened.
  def chips_for(category)
    return [] if category.blank?

    found = SuggestionEngine.new(user: current_user).by_category.fetch(category.id, [])
    @budget ? found.select { |suggestion| suggestion.subject == @budget } : found
  end

  # THE WORDS THE PREVIEW IS ABOUT. A submission carries every control on the form, so on the new
  # path this is simply what was typed; on an edit it is merged over the RULE's own words for
  # `#update`'s reason — a request naming only an amount must not strip a six-monthly bill of its
  # interval on the card any more than it may in the database.
  #
  # `category_id` IS DROPPED ON THE EDIT PATH, matching `#update_params`: the category is not
  # writable there, so it must not be previewable there either.
  #
  # ** `#scoped_owners` IS ON THIS PATH TOO, AND IT IS THE WHOLE OF §7a's POINT. ** The preview
  # RENDERS what it is handed — an item's name in a sentence, a category's in the breadcrumb — so an
  # unscoped id here is the read-shaped half of the same leak the POST closes: `POST /budgets/preview`
  # with a stranger's `item_id` would price a rule against THEIR spending and print their item's
  # name back. A stranger's id is a 404, the same answer every other owner on this controller gets.
  def preview_words
    submitted = scoped_owners(payload)
    return submitted if @budget.blank?

    RuleForm.from(@budget, user: current_user).merge(submitted.except(:category_id))
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
