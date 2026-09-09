# frozen_string_literal: true

# Everything the Budget page renders: every rule the user owns, grouped under the category it fills,
# in the order the money actually arrives. Read-only — the rule forms it links to own the writes.
#
# See docs/superpowers/specs/2026-08-15-budgeting-ui-design.md §8 and
# docs/superpowers/specs/2026-08-21-two-ledger-design.md §3
class BudgetPagePresenter
  # ** `Rule` AND `Group` ARE DELETED, AND THEIR ROW IS `ClaimLine` (this task). ** The two Data
  # types said in this file's words exactly what `HomePresenter::ClaimLine` and its block said in
  # Home's, and both files carried a comment promising the other would be kept in step by hand. They
  # were not (Home printed `$450.00 of $1,200.00` where this row printed `$450.00 built up of
  # $1,200.00`). There is one row type, in `app/presenters/claim_line.rb`, built by `ClaimRows` off
  # this page's ONE `ClaimLedger`; `#countable_span` and `#adjustments` — the two members only the
  # adjust panel reads — ride on it, filled here and empty everywhere else.
  #
  # ** ONE CATEGORY, AS THE LIST DRAWS IT (two-shapes spec §4). ** Every EXPENSE category the user
  # owns gets one of these, ruled or not:
  #
  #   `lines`            its rules as `ClaimLine`s, in give-way order — EMPTY for a rule-less one
  #   `type_dots`        one entry per rule, its type, for the dots beside the name
  #   `claimed`          Σ the lines' claims — the same figure `free` subtracted on Home
  #   `spent_recently`   `SuggestionEngine::Spending` for a rule-less category, nil for a ruled one
  #   `suggestion_count` how many of the engine's suggestions are about this category
  #   `open`             whether this is the one category expanded on this render
  #
  # `spent_recently` IS ONLY ASKED OF A RULE-LESS CATEGORY, and the asymmetry is the point: a ruled
  # category's spending is already in its rows (each rule's own lane, and the lanes partition —
  # §3.1), so a category-level figure beside them would be the same money said twice. A category with
  # no rule has no lane at all, and what it has instead is a fact about the entries.
  CategoryRow = Data.define(
    :category, :lines, :type_dots, :claimed, :spent_recently, :suggestion_count, :open
  ) do
    delegate :name, :priority, to: :category

    def open? = open

    def rule_count = lines.size

    def ruled? = lines.any?

    # DOES ANYTHING UNDER THIS NAME NEED A HUMAN — the same two facts Home's strip fires on, asked
    # of the same rows, so the two screens agree about one category on one afternoon.
    def needs_attention? = lines.any?(&:trouble?)

    def suggestions? = suggestion_count.positive?

    # ** IS THIS ROW DRAGGABLE — AND IT IS `Category.apply_fill_order`'S OWN POPULATION. ** That
    # endpoint refuses any list but `in_fill_order.with_a_rule`, so a row that drew a handle for
    # anything else would offer a control whose every use is refused — and the refusal would say
    # "that order didn't match your categories" about the order this page had just rendered. A
    # holder with a rule, asked of the record and of the rows this object already carries.
    def reorderable? = category.holder? && ruled?
  end

  # ** THE THREE TILES ACROSS THE TOP (two-shapes spec §4). ** One object rather than three, because
  # the three are one arithmetic: what the rules need, what comes in, and the subtraction between
  # them. A list of tiles would have made the partial branch on which tile it was rendering anyway,
  # and would have let the third be built from figures the first two did not print.
  #
  # `segments` IS THE TYPE BAR AND THE THREE TOTALS UNDER IT — one entry per kind of rule that
  # exists, in reading order, each carrying what it asks of a period and how wide its band is. The
  # PERCENT is here rather than in the view for `HomePresenter#claimed_percent`'s reason: a bar and
  # the figure beside it must be two readings of one number.
  Segment = Data.define(:type, :amount, :percent)

  Tiles = Data.define(:need, :segments, :income, :cadence, :leftover, :declared, :fits) do
    def declared? = declared

    # ** GREEN WHEN IT FITS, RED WHEN IT DOES NOT (§4). ** Both halves are required: an undeclared
    # user's tile is neither — it says "declare your income" — so a view branching on the sign of a
    # nil would have to know that too.
    def fits? = fits
  end

  attr_reader :user, :today

  # THE RECORD THE DECLARATION FORM EDITS, which is `user` on every path but one.
  #
  # A refused declaration leaves the rejected values and the errors on the in-memory user, and the
  # form must keep both — otherwise a validation failure silently throws away what was typed. But
  # the FIGURES must not read them: the row was not written, so a block computed from those values
  # would print "$2,400.00 a period" at a user whose income the database still holds as nil, under
  # a message saying the save failed. Measured in the browser, not reasoned about.
  #
  # Hence two objects on that one path: `user` for what is true, `declaration` for what was typed.
  # See BudgetPageController#update.
  attr_reader :declaration

  # `open_category_id:` IS WHICH CATEGORY IS EXPANDED ON THIS RENDER — the `open` query parameter,
  # threaded through rather than read off `params` here. Nil is a real answer (nothing expanded), and
  # it is the ordinary one: without JavaScript the chevron is a link that sets it, and with
  # JavaScript `category_list_controller` restores the viewer's last one out of localStorage.
  #
  # `declaring:` IS WHETHER THE DECLARATION FORM IS SHOWING (`?declare=1`). §4 hides it behind
  # "change" on the income tile, so it is a fact about this render rather than about the user.
  def initialize(user:, today: user.today, declaration: nil, open_category_id: nil, declaring: false)
    @user = user
    @today = today
    @declaration = declaration || user
    @open_category_id = open_category_id.presence&.to_s
    @declaring = declaring
  end

  # ** THE THREE TILES (§4). ** Everything the top of the page says, from the readers below it, so
  # the tile that says "left over" is arithmetically the two above it.
  def tiles
    @tiles ||= Tiles.new(
      need: rules_need,
      segments: segments,
      income: typical_income,
      cadence: user.period_cadence,
      leftover: leftover,
      declared: declared?,
      fits: fits?
    )
  end

  # ** EVERY EXPENSE CATEGORY THE USER OWNS, RULED ONES IN PRIORITY ORDER THEN RULE-LESS ONES BY
  # NAME (§4). ** Two populations and one list, because §4's list is the user's whole expense budget
  # and not only the part of it that has been written down yet: a category nobody has given a rule is
  # exactly where the next rule goes, and a page that omitted it would send that user hunting.
  #
  # ** THE ORDER IS PRIORITY — `Category.in_fill_order` — AND THAT IS THE FIX ROUND'S RULING
  # (MAJOR-1). ** It was `ClaimRows#blocks`' order, which is the GIVE-WAY order: type first, then
  # priority. A list ordered on a key the drag does not write cannot be dragged. Measured on Rent
  # (bill, priority 0) beside Fun (choice, priority 1), which give-way draws `[Fun, Rent]`: "move Fun
  # down" produced `[Fun, Rent]` again, `apply_fill_order` wrote Fun 0 and Rent 1, and the page came
  # back IDENTICAL under a flash saying the order had changed — while Rent's priority had moved
  # though the user never touched it. The type is what ranks first in the give-way walk and no arrow
  # can reach it, so the only honest thing for this list to draw is the number the arrows write.
  #
  # ** THE ROWS ARE STILL `ClaimRows#blocks`' — the same `ClaimLine`s and the same `claimed` — and
  # only the ORDER is this page's. ** Home draws the give-way order and says so; this page draws the
  # priority order and says so above the list. They are two readings of ONE set of rows, which is the
  # whole point of the shared reader: a category's rules and its claimed figure are identical on both
  # screens, and only the sentence each screen is answering differs.
  #
  # `[priority, name]` IS `Category.in_fill_order`'S OWN KEY, in memory. Priority alone is not a total
  # order, and a tie falling through to database order means the same data ranks differently between
  # loads — and `apply_fill_order` walks `in_fill_order` when it renumbers, so a page sorted any other
  # way would be dropping the dragged category into a slot list it does not share.
  #
  # ** THE RULE-LESS HALF IS BY NAME, and that is a refusal rather than an omission. ** These
  # categories have no rule, so they have no priority the reorder can write and no claim to rank by;
  # sorting them by what has been SPENT there would imply an order the app is not asking for.
  def category_rows
    @category_rows ||= ruled_rows + unruled_rows
  end

  # THE ROWS THE DRAG AND THE ▲▼ WRITE, in the order they are drawn — `Category.apply_fill_order`'s
  # own population (see `CategoryRow#reorderable?`). `_reorder_controls` takes this list, because
  # every button carries the WHOLE order as hidden fields and a list including a row the endpoint
  # refuses would make every one of those buttons a refusal.
  def reorderable_rows = @reorderable_rows ||= category_rows.select(&:reorderable?)

  # WHICH CATEGORY'S PANEL IS OPEN, or nil. Compared as a string, because it arrives off the wire.
  def open?(category) = @open_category_id.present? && @open_category_id == category.id.to_s

  # IS THE DECLARATION FORM SHOWING — `?declare=1`, or a submission that was refused (the form holds
  # what was typed and the errors, and hiding it would throw both away).
  def declaring? = @declaring || declaration.errors.any?

  # THE SUGGESTIONS FOR ONE CATEGORY, and the hidden ones with them — both off the page's ONE engine,
  # partitioned there (`SuggestionEngine#by_category`) rather than filtered here.
  def suggestions_for(category) = by_category.fetch(category.id, [])

  def hidden_suggestions_for(category) = hidden_by_category.fetch(category.id, [])

  # ** WHAT EACH KIND OF RULE COSTS A PERIOD (rules-own-the-budget spec §3) — the overview above the
  # groups. ** `[[:bill, 1_400], [:usage, 600], [:choice, 300]]`, which the partial renders as
  # `Bills $1,400.00 · Usage $600.00 · Choice $300.00 a period`.
  #
  # ** `#standing_ask` AND NOT `#claim`, WHICH IS THE SAME CHOICE §9'S STRUCTURAL CHECK MAKES. ** The
  # overview is a sentence about the SHAPE of the budget — how much of a typical period is spoken for
  # by things that must be paid — and `Σ claims` is this afternoon's answer: catch-up on anything
  # behind, zero on anything already full, so the same three rules would report different splits on
  # two consecutive days with nothing edited. `ClaimCalculator#standing_ask` is a constant of the rule
  # and the grid, which is what makes these three figures add up to `#rules_need` two blocks down.
  #
  # OVER `#rules` — EVERY RULE THE USER OWNS, the same population `Budget.steady_need` sums and
  # therefore the same one the structural check compares against income. It deliberately includes
  # `#unfilled_rules`: those are claims on income that no group can show, and an overview that
  # omitted them would split a total the check below prints whole.
  #
  # ** OFF THE PAGE'S ONE LEDGER (§3.3). ** `claim_ledger.calculator_for` rather than
  # `Budget#steady_ask`, whose one-off arm BUILDS a calculator of its own — that is the second-door
  # defect `EntryImpactPresenter#steady_claim` closed, and it would be a fresh calculator per dated
  # bill on the one page that already holds one for every rule. `#standing_ask` reads no rows, so
  # this costs no statement at all and the page's strict-`eq` cost pin is unmoved.
  #
  # BILL, USAGE, CHOICE — THE READING ORDER, WHICH IS `Budget::TYPE_RANK` BACKWARDS. The give-way
  # order runs the other way (choice gives way first, §3), and that is not a contradiction: this
  # line is read as "what is unavoidable, then what moves with how you live, then what you choose",
  # heaviest commitment first. A TYPE WITH NO RULES IS OMITTED rather than printed as `$0.00` — a
  # figure that is true and reports nothing, on a line whose whole job is the split.
  TYPE_OVERVIEW_ORDER = [:bill, :usage, :choice].freeze

  def type_overview
    @type_overview ||= begin
      asks = rules.group_by { |budget| budget.rule_type.to_sym }
      TYPE_OVERVIEW_ORDER.filter_map do |type|
        group = asks[type]
        next if group.nil?

        [type, group.sum(0.to_d) { |budget| claim_ledger.calculator_for(budget).standing_ask }]
      end
    end
  end

  # THE EMPTY STATE'S GATE (`_empty.html.erb`): a user with no EXPENSE CATEGORY AT ALL. It was
  # `#rules.empty?` — "no rules" — and the list is every expense category now, so a user with three
  # categories and no rules has three rows to write a rule from and is not empty at all. The one user
  # this page has nothing to draw for is the one with nowhere to put a rule.
  def no_categories? = category_rows.empty?

  # §8's structural check, three lines: what the rules claim from a period, what the user says
  # they bring in, and the difference.
  #
  # `Budget.steady_need`, NOT a sum over #rules — even though #rules is already loaded and
  # preloaded, and this therefore costs a second pass over the same rows. The figure is read by
  # this page, by Home's standing band and by the sacrifice view, and the moment two of
  # them spell the sum themselves they are free to disagree about which rules count. One reader,
  # measured: see the query note in the task report.
  #
  def rules_need = @rules_need ||= Budget.steady_need(user, today: today, ledger: claim_ledger)

  # NIL, NOT ZERO, for a user who has not declared one. Zero is a claim — "you bring in nothing"
  # — and it would make every user with a single rule read as underwater on a screen they have
  # not yet told anything. The block renders its invitation off this nil.
  #
  # `.to_d` because the comparison and the subtraction below both meet `rules_need`, which is
  # always BigDecimal. The `money` column casts, but an in-memory user assigned
  # `typical_income: 2400` holds the Integer.
  def typical_income = user.typical_income&.to_d

  # What is left after every rule is funded — the third line of §8, and the buffer's own source.
  # Nil wherever #typical_income is, because there is nothing to subtract from.
  def leftover = typical_income && (typical_income - rules_need)

  # §9's gate, and the ONE state the sacrifice button renders in.
  #
  # Steady need against declared income, never THIS period's Σ claims against it — the structural
  # question is what the rules ask of a TYPICAL period, and the two diverge in both directions on the
  # same budget. The steady figure is a constant of the rules and the grid on every shape, one-time
  # bills included (`ClaimCalculator#standing_ask`, fix wave 2 — MED-A), so nothing a user spends or
  # pays this afternoon can turn this block on or off. See Budget#steady_ask and
  # HomePresenter#structurally_underwater?.
  #
  # `declared?` AND NOT `typical_income.present?`, WHICH IS THIS FIX ROUND'S CORRECTION. The gate
  # used to ask only about the income, and it was unreachable in the wrong state only because the
  # view happens to nest this inside `if declared?` — a layout fact protecting a money comparison,
  # which is not a gate at all. A user with an income and NO CADENCE reaches `rules_need` through
  # `Budget#steady_ask`, which treats the period as a calendar month: comparing a monthly need
  # against an income whose period nobody has declared is two units in one `>`, and it decides
  # whether the app offers to cut the user's budget. Closed at the reader, so no second caller can
  # inherit the view's accident.
  #
  # THE APP NOW SPELLS THE SAME COMPARISON THREE TIMES AND ALL THREE AGREE — this,
  # `HomePresenter#structurally_underwater?` and `SacrificePresenter#gap` — each gated on a
  # declaration that includes the cadence. An undeclared income is not "covered", it is unanswered,
  # and the block says so rather than showing a button for a comparison nobody has made.
  def underwater? = declared? && rules_need > typical_income

  # Whether the check has anything to check. Both halves are required: without a cadence
  # `rules_need` still answers (Budget#steady_ask treats the period as a month) but it answers
  # about a period the user has not agreed to, and printing "$1,668 a period" at someone who has
  # not said how long a period is states a figure with no unit.
  def declared? = user.typical_income.present? && user.period_cadence.present?

  # ** `#suggestions`, `#hidden_suggestions` AND `#suggestions_by_kind` ARE DELETED WITH THE
  # STANDALONE PANEL (two-shapes spec §4/§7). ** They fed one page-wide list with an index strip
  # across the top of it, and §4 moves every suggestion inside the category it is about: the index
  # was navigation for a 5,000px panel that no longer exists, and a page-wide list would now be the
  # same rows a second time. `#suggestions_for` and `#hidden_suggestions_for` above are what
  # replaced them, off `SuggestionEngine#by_category` — ONE partition of the engine's own list, so
  # nothing is dropped and nothing is listed twice. The dismiss control and its "where did it go"
  # answer survive per category (Henry's ruling of 2026-08-20 is about the CONTROL, not about where
  # the panel sits).

  private

  # ONE ENGINE FOR THE PAGE. #suggestions and #hidden_suggestions are its two answers about one
  # run of the four detectors, and it holds the dismissal lookup they are split by.
  def engine = @engine ||= SuggestionEngine.new(user: user, today: today)

  # `#rules` IS `ClaimLedger#rules` NOW, AND THE PAGE'S KNOWN DUPLICATE IS GONE WITH IT (the four
  # statements the old cost pin named as lines 5-8). This class loaded `user.all_budgets` and the
  # ledger loaded `Budget.for_user` — two spellings of one population, each with its own
  # `includes(:item, category: :user)`, so the page paid for the same rows and the same three
  # preloads twice. There is one rule set on this page: the ledger's, which is what every figure on
  # it was computed from anyway.
  def rules = claim_ledger.rules

  # ** THE RULED ROWS, OFF `ClaimRows#blocks` — the give-way order grouped back (§4). ** Not
  # re-sorted and not re-grouped: this is Home's own section with three more facts hung on it.
  def ruled_rows
    claim_rows.blocks
      .sort_by { |block| [block.category.priority, block.category.name] }
      .map { |block| row_for(block.category, lines: block.rows, claimed: block.claimed) }
  end

  # ** EVERY EXPENSE CATEGORY WITH NO RULE, BY NAME. ** One statement for the whole list, with the
  # ruled half subtracted in memory, so a user's whole budget costs one query however it splits.
  def unruled_rows
    ruled = claim_rows.blocks.to_set { |block| block.category.id }

    expense_categories.reject { |category| ruled.include?(category.id) }
      .map { |category| row_for(category, lines: [], claimed: 0.to_d) }
  end

  def row_for(category, lines:, claimed:)
    CategoryRow.new(
      category: category,
      lines: lines,
      type_dots: lines.map(&:stripe_type),
      claimed: claimed,
      # THE WINDOW FIGURE IS ONLY ASKED OF A RULE-LESS CATEGORY (see `CategoryRow`), and it is the
      # ENGINE's own window — no second piece of date arithmetic on this page.
      spent_recently: lines.empty? ? engine.recent_spending[category.id] : nil,
      suggestion_count: suggestions_for(category).size,
      open: open?(category)
    )
  end

  # EVERY EXPENSE CATEGORY THE USER OWNS, in name order — the rule-less half of the list, and the
  # set the ruled half is subtracted from. `Category.in_fill_order` is deliberately NOT the reader:
  # that scope is holders only, and §4's list is every expense category including the ones that have
  # never held anything.
  def expense_categories
    @expense_categories ||= user.categories.spendable.order(:name).to_a
  end

  # ** THE ROWS, THE ORDER AND THE GROUPING — `ClaimRows`, SHARED WITH HOME (this task). ** It
  # queries nothing: the calculators are this page's ONE ledger's, and `categories:` is the
  # already-loaded expense list narrowed to the holders — `Category.in_fill_order`'s population in
  # memory rather than a second query for it.
  def claim_rows
    @claim_rows ||= ClaimRows.new(
      ledger: claim_ledger,
      today: today,
      categories: expense_categories.select(&:holder?),
      adjustments: adjustments_this_period
    )
  end

  # ** THE TYPE BAR AND ITS THREE TOTALS (§4), off `#type_overview`'s own figures. ** The percent is
  # each kind's share of what the rules need — the same total the tile prints above the bar, so the
  # bands add to the figure and not to something near it. No segments for a user with no rules, which
  # is the tile reading $0.00 and drawing no bar.
  def segments
    total = type_overview.sum { |(_type, amount)| amount }
    return [] unless total.positive?

    type_overview.map do |(type, amount)|
      Segment.new(type: type, amount: amount, percent: ((amount / total) * 100).round.clamp(0, 100))
    end
  end

  # DOES THE BUDGET FIT — the green/red gate on the third tile. `#underwater?` inverted, with the
  # declaration required on both sides: an unanswered income is not "it fits", it is unanswered.
  def fits? = declared? && !underwater?

  delegate :by_category, :hidden_by_category, to: :engine

  # ONE CLAIM LEDGER FOR THE WHOLE PAGE (computed-claims spec §3.3) — three statements for the
  # user's entire rule set, where a calculator per row would be two per rule. It is built over
  # `Budget.for_user`, which is every rule this page can render including the ones in
  # #unfilled_rules, so `#calculator_for` never has to be guarded against a row it does not know.
  #
  # LAZY, as `#ledger` is and for the same reason: this page writes nothing, so there is no deletion
  # for a snapshot to fall the wrong side of.
  #
  # PINNED, not asserted: `budget_page_presenter_spec`'s "costs the same number of statements for
  # five rules as for one" counts them, because a row that quietly grew a calculator of its own is
  # invisible to every other example in that file.
  def claim_ledger = @claim_ledger ||= ClaimLedger.new(user, today: today)

  # THIS PERIOD'S DELTAS, BY RULE — one statement for the page, and the rows themselves rather than
  # a sum, because the row lists each one with its date and a remove button.
  #
  # ONE DAY OF SLACK ON EITHER SIDE, THEN FILTERED IN RUBY, which is `ClaimLedger#window`'s idiom
  # for the same reason: the bound is a UTC instant and the day it protects is the OWNER's, so the
  # query is deliberately wide and `Adjustment#local_day` — the app's one re-zoning — decides
  # membership. A bare timestamp range would drop a Tokyo evening's top-up from its own period.
  #
  # THE PRELOAD IS WHAT KEEPS `#local_day` FREE. It walks `rule → category → user` for the zone, so
  # without it the filter above and the date the row prints are two lookups per delta — the very
  # per-row cost `#claim_ledger` exists to avoid, arriving through the back door.
  def adjustments_this_period
    @adjustments_this_period ||= begin
      period = user.period_containing(today)
      Adjustment.where(rule_id: rules.map(&:id))
        .includes(rule: { category: :user })
        .dated_within((period.first - 1).beginning_of_day..(period.last + 1).end_of_day)
        .order(:date, :created_at)
        .select { |adjustment| period.cover?(adjustment.local_day) }
        .group_by(&:rule_id)
    end
  end

  # ** `#rule_order` LEFT WITH THE ROW (`ClaimRows`). ** Ordering a category's rules is the shared
  # reader's job now — `Category.rule_order` over the date the row actually prints — and a copy here
  # would be this page free to list one category's rules in a different order from Home's.
end
