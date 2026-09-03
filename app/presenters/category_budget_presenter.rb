# frozen_string_literal: true

# THE CATEGORIES PAGE'S HOLDINGS CARD — what this category holds, in the two states an expense
# category can be in. Read-only: it has nothing to write.
#
# TWO ARMS, AND THE LINE BETWEEN THEM IS `Category#holder?` (two-ledger spec §3, §4). A category
# either holds money of its own — an expense category with a `funded_since` — or it does not, in
# which case its spending drains AVAILABLE, money with no job yet. That is one column and one
# predicate, where the pool era needed a pool, a pool TYPE and a start date to answer the same
# question.
#
# IT SERVED TWO CARDS AND NOW SERVES ONE (Task 7). `_budget_card` said how the envelope stood in
# the row vocabulary; `_pool_card`, four inches below it, drew the same pool again with a name, a
# progress bar and a noun of its own. They spent three review rounds converging on one vocabulary —
# the three-noun defect ("Envelope" / "Savings Pool" / "goal", one pool, one afternoon) was the
# loudest of them — and the convergence is now structural: there is one card, so there is nothing
# to disagree with.
#
# THE GOAL TEST IS THE CALCULATOR'S, NOT `Category#savings?` (Task 7's carried-inconsistency
# ruling). `savings?` is holder + target + NO RULE, so a goal the user also refills at a rate — the
# demo's Retirement Supplement — read as an envelope here and on the entry form.
# `HoldingCalculator#saving_toward_a_target?` is the predicate the sweep already runs on ("savings
# never sweep, whatever their rule mix"), and it is what this card's HEADING and its target bar ask.
#
# TWO LEVELS, DELIBERATELY (fix round 1, MED-2). The CHROME — `Goal` or `Envelope`, bar or no bar —
# is that predicate, here and on the impact card and the index card alike. The STANDING line below
# it is `HoldingStatus`, which stays schedule-aware through `HoldingCalculator#dateless_goal?`: a
# DATELESS goal reads `saving`, and a goal carrying an anchor-dated rule reads `on track` / `behind`
# / `won't make it`, because it has a deadline the anchored maths can measure. `Goal · on track` is
# therefore a sensible pairing rather than the two halves of this card disagreeing — see
# `HoldingCalculator#dateless_goal?` for the whole argument.
#
# See docs/superpowers/specs/2026-08-21-two-ledger-design.md §3–§4 and
# docs/superpowers/specs/2026-08-15-budgeting-ui-design.md §8.1.
class CategoryBudgetPresenter
  attr_reader :category, :today

  # `today` DEFAULTS TO THE OWNER'S DAY (`Category#today` → `User#today`) AND IS NOT THE PAGE'S
  # `selected_date`. The category page has a
  # period toggle and can be read for a month that is over; what a category HOLDS is a fact about
  # NOW (§4.1 — the time word cannot be dropped), and rendering last March's row vocabulary beside
  # a live "Rules on the Budget page" button would be the page disagreeing with the screen it links
  # to. The spending figures above this card are the ones the toggle is for.
  def initialize(category:, today: category.today)
    @category = category
    @today = today
  end

  # ---- Which state the card is in ---------------------------------------------------------------

  # ONE READER FOR WHICH ARM RENDERS, because the card also stamps the state into the DOM for the
  # specs to scope by, and a `data-` attribute computed separately from the branch is free to name
  # an arm the page did not render — which would make a scoped assertion pass against the wrong
  # state and read as green. Both come from here.
  def state = category.holder? ? :holding : :unfunded

  def holding? = state == :holding

  # ** MONEY IN A CATEGORY THAT IS NOT A HOLDER (final fix wave, I-1, belt). ** The unfunded arm's
  # sentence is "this category doesn't hold money yet", and the one shape that makes it a lie is a
  # non-holder whose balance is not zero — allocations sitting in a category whose `funded_since` is
  # NULL. §2's partition still counts that money; every screen that reads `holder?` stops looking at
  # it.
  #
  # UNREACHABLE ONCE THE TWO GUARDS IN THIS WAVE LAND, and rendered anyway. `AllocationsController`
  # stamps the date on the way in and `Category#money_may_not_be_stranded` refuses to clear it on the
  # way out, so no live path produces this state — but it is PLANTABLE (an `update_column`, a console,
  # an import, a row from before this wave), and a page that says $0 over $400 of the user's money is
  # the worst of the three possible answers. The card tells the truth and names the door out.
  #
  # `#balance` READS FOR A NON-HOLDER, which is why this costs nothing extra: `HoldingCalculator
  # #balance` is allocations in, less allocations out, less the spending `Entry.draining` attributes —
  # and for a NULL `funded_since` that last term is zero by `CategoryLedger::ENTRY_CATEGORY_ID`'s own
  # arm. So the figure is exactly the stranded allocations, on the calculator this class already
  # memoises.
  def stranded? = !holding? && !balance.zero?

  # ---- The holding arm --------------------------------------------------------------------------

  # ONE CALCULATOR AND ONE STATUS FOR THE CARD, so the balance, the bar and the words beside them
  # cannot disagree — the same objects the Budget page's group header and Home's category row are
  # built from, which is what keeps all three screens describing one category in one vocabulary on
  # one afternoon.
  #
  # No `CategoryLedger`: a ledger's whole point is answering for a SET of categories in grouped
  # queries, and this page renders exactly one.
  def status = @status ||= category.status(today: today)

  def calculator = @calculator ||= category.holding_calculator(today: today)

  # THE ROW VOCABULARY'S FOUR QUESTIONS, so this presenter can be handed straight to
  # `shared/_holding_status` exactly as `HomePresenter::Row` and `BudgetPagePresenter::Group` are.
  # An object either answers all four or raises on the first render, which is the property that
  # partial exists for — see its header.
  #
  # `balance_clause?` true and `due_marker?` false: the card prints the balance in its own right
  # beneath the status, and a bare date would be a rule's date with nothing saying which rule.
  delegate :needs_attention?, :period_closed?, to: :status
  def balance_clause? = true
  def due_marker? = false

  # WHAT THIS CATEGORY HOLDS. Off the calculator this class already holds, never a second one: two
  # objects for one balance is how two figures on one page come to disagree.
  delegate :balance, to: :calculator

  # IS THIS A GOAL — asked of the calculator, which is the whole of the ruling above. Also the
  # gate on the progress bar, because `#progress_percentage` measures a balance against a target
  # and a category without one has nothing for a bar to be a fraction of.
  delegate :saving_toward_a_target?, :progress_percentage, :remaining_amount, to: :calculator

  def target = category.target_amount.to_d

  # THE RULES THAT FILL THIS CATEGORY, named. `budgets.category_id` is a rule's owner since Task 5,
  # so this is the category's own association rather than a pool's — the card lists what the Budget
  # page would show under this category's group header, and links there rather than offering an
  # editor of its own.
  #
  # `includes(:item)` because `HomeHelper#pool_rule_label` names a rule by its item where it has
  # one, which is the ordinary shape for a dated bill.
  def rules = @rules ||= category.budgets.includes(:item).order(:anchor_date, :created_at).to_a

  def rules? = rules.any?

  # WHEN THIS CATEGORY STARTED HOLDING MONEY (§4). Printed rather than alluded to, because it is
  # the only thing on the card that says WHICH of the user's spending the balance above it covers:
  # anything earlier drained available.
  delegate :funded_since, to: :category

  # BOTH SUFFIXES, and this screen owes both for the reason `HomeHelper#pool_status_label`'s comment
  # gives: this card says how the category STANDS RIGHT NOW, so a clause here and not on Home is
  # two screens describing the same category differently. `period_closed?` rides on the status's own
  # calculator; this one is a question about the SCREEN's period, which a status cannot answer.
  #
  # `defined?` rather than `||=`, because the answer is false for most categories most of the time
  # and `||=` would re-run the clock's query on every call for exactly those — the memo would work
  # only where it was not needed.
  def changed_after_distributing?
    return @changed_after_distributing if defined?(@changed_after_distributing)

    @changed_after_distributing = DistributionClock
      .new(user: category.user, today: today)
      .changed_after_distributing?(category)
  end

  # ---- The unfunded arm -------------------------------------------------------------------------

  # WHETHER THE BUDGET PAGE IS CURRENTLY PROPOSING A RULE FOR THIS CATEGORY — §8.1 put this on its
  # third state, which is deleted; the unfunded arm is the one that carries it now, and a rule (or
  # an allocation) is that category's only way out of it.
  #
  # `SuggestionEngine` itself, never a re-derivation of the four detectors' conditions: the pointer
  # exists to say that something is waiting on /budget, and a second reader of "is there" that
  # disagreed with the panel would send the user to an empty list — or, worse, stay silent over a
  # real one.
  #
  # THE COST, AND WHY IT IS PAID ON ONE ARM ONLY. The engine is 8 queries and ~14ms warm on the
  # demo's three-year history against a page that costs 14 queries and ~76ms. A holder category
  # never runs it. Gated at the reader rather than in the view so no second caller can inherit the
  # run without the state that justifies it.
  def suggestions
    return [] unless proposable?

    # `dig(:budget, :category_id)` IS THE ENGINE'S OWN ANSWER to "which category would accepting
    # this move" (Task 5 collapsed the prefill into ONE hash, and the flat read left here answered
    # nil for every suggestion — this pointer went silent on every category in the app).
    @suggestions ||= engine_suggestions.select do |suggestion|
      suggestion.prefill.dig(:budget, :category_id) == category.id
    end
  end

  def suggested? = suggestions.any?

  # WHICH RUN ON /budget TO LAND IN. The engine's order is kind rank first (dated bills before
  # rates), so the first suggestion's kind is the most urgent thing waiting there, and
  # `suggestion_kind_anchor` is the same reader the panel's own index and headings use — one
  # spelling of the fragment, so this link cannot silently stop working.
  def first_suggestion_kind = suggestions.first&.kind

  private

  # WHETHER A PROPOSAL COULD BE ABOUT THIS CATEGORY AT ALL — ONE CONDITION, and it stays one.
  #
  # IT WAS `Category#buffer_funded?` AND THAT IS A POOL READER (Task 7). `SuggestionEngine
  # #unfunded_categories` is `expense_categories.reject(&:holder?)` — literally this arm's own
  # population — so the gate and the detector it gates are the same predicate rather than two that
  # can drift. Under the two-ledger model they had already inverted for the shapes this branch
  # mints: a category that holds its own money is precisely the one whose `pool` is nil, which
  # `buffer_funded?` answers false for and `holder?` answers true for.
  #
  #   holds nothing → asks   (the unfunded arm's only way out)
  #   holds money   → silent (the holding arm)
  #
  # Asked of the model rather than of #state's symbol so an edit to the state names cannot widen
  # the gate, and written as a predicate rather than `state == :unfunded` so there is one place a
  # future arm has to be argued into.
  def proposable? = !category.holder?

  def engine_suggestions = SuggestionEngine.new(user: category.user, today: today).suggestions
end
