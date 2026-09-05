# frozen_string_literal: true

# ** EVERY RULE'S `ClaimLine`, AND THE TWO ORDERS THE SCREENS READ THEM IN — ONE PLACE (this task).
# **
#
# It was `HomePresenter`'s private half: `#claim_lines`, `#give_way_order`, `#give_way_key`,
# `#give_way_rank`, `#category_blocks` and the `ClaimLine` type itself. The Budget page is the same
# list under a different header (spec §4: "the list … Order = give-way order"), and the categories
# card is one category's slice of it — so leaving the sort on Home meant either a second sort
# (which is how the trouble strip came to rank a category the section below it ranked differently,
# the defect `HomePresenter#category_blocks` records) or the Budget page reaching into Home's
# privates. It is hoisted HERE, and Home, the Budget page and the categories card are three readers
# of one list.
#
# ** NOTHING HERE QUERIES. ** The rules, their calculators and their spending come off the
# `ClaimLedger` the caller already holds; the period grid is `User#period_containing`, pure Ruby;
# `categories:` is the caller's own already-loaded list. That is what lets three screens share this
# without any of them paying for a fourth statement — and it is why the cost pins on Home and on
# the Budget page did not move when this class appeared.
class ClaimRows
  # ONE CATEGORY AND ITS RULES, IN GIVE-WAY ORDER (two-shapes spec §3). Home renders it as a block;
  # the Budget page builds its own row around it (`BudgetPagePresenter::CategoryRow`), because that
  # list carries three things Home's does not — a type dot per rule, a suggestion count and whether
  # the category is open.
  #
  # `spent` IS NOT HERE and that is deliberate: each line already carries its own lane's spending
  # and the lanes partition (§3.1's `Entry.on_unruled_items`), so a category-level sum beside them
  # would be the same money said twice.
  CategoryBlock = Data.define(:category, :rows, :claimed) do
    delegate :name, to: :category

    def rule_count = rows.size

    # ** THE HEADER TINT (two-shapes spec §3): "a category in trouble — any rule over, short or
    # overdue — tints its header". **
    #
    # IT IS A WIDER TEST THAN `ClaimLine#trouble?`, DELIBERATELY, AND THE DIFFERENCE IS `short?`.
    # That predicate is the TROUBLE STRIP's population, and §5 gives the strip exactly two per-rule
    # triggers — spending past the rate, and a date gone by unpaid. A bill due on the 20th with $80
    # of its $120 saved is neither: nothing has gone wrong yet, the runway names it in its pace
    # line, and the block tints so the eye lands there.
    def trouble? = rows.any? { |row| row.trouble? || row.short? }
  end

  attr_reader :ledger, :today

  # `categories:` IS THE CALLER'S `Category.in_fill_order` LIST, and it is required only by
  # `#give_way_order` — the categories card never asks for the order and therefore never has to
  # load one. A caller that omits it and then asks for the order gets the list loaded here, once.
  #
  # `adjustments:` IS `{ rule_id => [Adjustment] }`, THIS PERIOD'S DELTAS, and only the Budget page
  # fetches them (it lists each one with a remove button). Every other caller passes nothing and the
  # rows carry `[]` — an empty array is an answer, on `ClaimCalculator#spending_rows`' own rule.
  def initialize(ledger:, today: ledger.today, categories: nil, adjustments: {})
    @ledger = ledger
    @today = today
    @categories = categories
    @adjustments = adjustments
  end

  delegate :user, to: :ledger

  # ** EVERY RULE'S CLAIM, BY CATEGORY. ** Built once for the whole screen: the category blocks, the
  # trouble strip's triggers and the shortfall's give-way walk are three readings of ONE list, and
  # three lists would be three chances for the strip to name a category the section below it
  # describes differently.
  #
  # ** `Category.rule_order`, WHICH IS THE APP'S ONE KEY. ** It orders on the date the row PRINTS
  # (`ClaimCalculator#next_due_on`, which rolls on payment) rather than on the `anchor_date` column,
  # so a line never sits above its neighbour for a reason the screen contradicts. THE LINES ARE
  # BUILT BEFORE THEY ARE SORTED, because the key reads that date and it is the claim's reading
  # rather than a column.
  def lines_by_category
    @lines_by_category ||= lines
      .sort_by { |line| Category.rule_order(next_due_on: line.next_due_on, amount: line.rule.amount, id: line.rule.id) }
      .group_by { |line| line.category.id }
  end

  # ONE CATEGORY'S LINES. `fetch` with a default rather than `[]`, because a category with no rule
  # is a real caller — Home's trouble walk and the Budget page's list both ask about one.
  def lines_for(category) = lines_by_category.fetch(category.id, [])

  # ** THE ORDER CLAIMS GIVE WAY IN (rules-own-the-budget spec §3), AND IT IS ONE SORT OVER EVERY
  # CLAIM LINE. ** The type is a fact about a RULE — one category may carry a bill beside a choice —
  # so every line is ranked individually, on one key:
  #
  #   1. `Budget#type_rank` — `{ choice: 0, usage: 1, bill: 2 }`, spelled once on the model (§3).
  #      Discretionary money goes first and a must-pay is the last thing reached. It DECIDES BEFORE
  #      PRIORITY DOES: a restaurant rule on a high-priority category gives way before the rent.
  #   2. THE CATEGORY, IN REVERSE FILL ORDER — `#ranked_categories` read backwards, which is
  #      `[priority, name]` reversed. The category that would have been funded LAST goes without
  #      first, so a HIGHER priority number gives way sooner; a tie breaks on the later NAME.
  #   3. `Category.rule_order` — the app's one within-category key, so two rules of one type on one
  #      category give way in the order the rows are printed in.
  def give_way_order
    @give_way_order ||= lines_by_category.values.flatten.sort_by { |line| give_way_key(line) }
  end

  # ** THE BLOCKS ARE `#give_way_order` GROUPED BACK, AND THAT IS THE WHOLE OF THE SORT (§3). **
  # `group_by` KEEPS FIRST-APPEARANCE ORDER, which is exactly the rule the spec states: a block's
  # position is its FIRST line's position in the walk, so a category is placed by the rule of its
  # that gives way soonest. No second sort exists to disagree with the strip's list.
  def blocks
    @blocks ||= give_way_order.group_by { |line| line.category.id }.map do |_id, rows|
      CategoryBlock.new(category: rows.first.category, rows: rows, claimed: rows.sum(0.to_d, &:claim))
    end
  end

  # WHICH PERIOD THESE ROWS ARE READ AGAINST, or nil for a user who has declared none.
  #
  # `User#period_containing`, the one method that owns this arithmetic. GATED ON THE DECLARATION
  # rather than taken on trust: that method falls back to the calendar month for an undeclared user,
  # which is the right fallback for a normaliser and a lie on a card, since "Aug 1 – Aug 31" would
  # state a boundary the user never set.
  #
  # MEMOISED WITH `defined?`, because the nil arm is a real answer and the common one for an
  # undeclared user — `||=` would re-walk the boundaries once per rule for exactly the users who
  # have none.
  def period_range
    return @period_range if defined?(@period_range)

    @period_range =
      if user.period_cadence.blank? || user.period_anchor_date.blank?
        nil
      else
        user.period_containing(today)
      end
  end

  # EVERY CATEGORY A CLAIM LINE CAN BELONG TO, in `Category.in_fill_order`'s own key — the holders,
  # PLUS any category carrying a rule that is not one (`funded_since` cleared after the fact). The
  # second half is load-bearing rather than defensive: `ClaimLedger` counts EVERY rule's claim into
  # `free`, so a claim whose category had no rank would have no place in the give-way walk.
  def ranked_categories
    @ranked_categories ||= (categories + ledger.rules.filter_map(&:category))
      .uniq.sort_by { |category| [category.priority, category.name] }
  end

  private

  def categories = @categories ||= user.categories.in_fill_order.to_a

  def lines = @lines ||= ledger.rules.map { |rule| build_line(rule) }

  def build_line(rule)
    calculator = ledger.calculator_for(rule)

    ClaimLine.new(**figures(calculator), **context(rule, calculator))
  end

  # THE CALCULATOR'S OWN ANSWERS, in one read of one object — a row cannot pair one rule's figure
  # with another's state, which is the whole reason these are members rather than a calculator the
  # row holds on to.
  def figures(calculator)
    {
      shape: calculator.shape,
      claim: calculator.claim,
      spent: calculator.spent_this_period,
      accrued: calculator.accrued_this_period,
      built_up: calculator.built_up,
      target: calculator.target,
      next_due_on: calculator.next_due_on,
      per_period: calculator.planned_this_period,
      over: calculator.over?,
      over_by: calculator.over_by,
      overdue: calculator.overdue?,
      paid: calculator.settled?,
      paid_on: calculator.settled_on,
      countable_span: calculator.countable_span
    }
  end

  # WHAT THE CALCULATOR CANNOT KNOW: the rule's owner, the page's period window, and the deltas only
  # the Budget page fetches.
  def context(rule, calculator)
    {
      category: rule.category,
      rule: rule,
      due_this_period: due_this_period?(calculator.next_due_on),
      resets_on: calculator.rate? ? next_period_opens_on : nil,
      adjustments: @adjustments.fetch(rule.id, [])
    }
  end

  # ** THE DAY A RATE RULE STARTS AGAIN (§3: "resets Oct 1"). ** Use-it-or-lose-it is reset at every
  # boundary (§3.1), so the day is the one after this period's close — `#period_range`'s own last
  # day, never a second calendar. Nil for a dated rule (nothing resets; it has a due date instead)
  # and for a user who has declared no period, where the row simply says one clause fewer.
  def next_period_opens_on = period_range.nil? ? nil : period_range.last + 1

  # ** IS THE DAY THIS RULE'S MONEY IS NEEDED ON INSIDE THE PERIOD ON THE SCREEN? ** Nil for a user
  # who has declared no period, where the honest answer is false rather than a month nobody set.
  def due_this_period?(due) = due.present? && period_range.present? && period_range.cover?(due)

  # ONE LINE'S PLACE IN THE GIVE-WAY ORDER. See #give_way_order for what each term is and why.
  def give_way_key(line)
    [
      line.rule.type_rank,
      give_way_rank.fetch(line.category.id),
      Category.rule_order(next_due_on: line.next_due_on, amount: line.rule.amount, id: line.rule.id)
    ]
  end

  # THE CATEGORY HALF OF THE KEY: `#ranked_categories` READ BACKWARDS, AS AN INDEX. The negated
  # position in a list already sorted `[priority, name]`, so the reverse-fill order arrives as one
  # comparable number and `Category.in_fill_order`'s key is not written out a second time. Every
  # line's category is in that list by construction, so `fetch` is a claim rather than a lookup.
  def give_way_rank
    @give_way_rank ||= ranked_categories.each_with_index.to_h { |category, index| [category.id, -index] }
  end
end
