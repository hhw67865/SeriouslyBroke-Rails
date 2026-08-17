# frozen_string_literal: true

# THE CATEGORIES PAGE'S BUDGET BLOCK, in the states spec §8.1 gives it — PLUS ONE THE SPEC DOES NOT
# NAME. Read-only: the cap form it links to owns the writes, and the other arms have nothing to
# write at all.
#
# THE STATES ARE DISJOINT AND EXHAUSTIVE FOR AN EXPENSE CATEGORY, and not by arrangement here:
# `Budget#category_must_not_have_pool` refuses a cap on a category that points at ANY pool, so no
# pooled arm can also be capped, and "no pool, no cap" is the remainder.
#
# THE FOURTH STATE IS `:account_pointed`, AND IT IS A CORRECTION MADE IN REVIEW. §8.1 divides the
# world into "points at an envelope" and "budgetable" (`Category#budgetable?` — no pool at all), and
# a category pointing at an ACCOUNT is in neither: `pool_covered?` admits it (any pool), so the
# first version of this block told such a category it had an envelope, named the ACCOUNT as that
# envelope, printed the account's whole balance as this one category's standing, and spoke of "the
# rule that fills the envelope" — which `Budget#pool_must_not_be_an_account` guarantees can never
# exist. Every clause was false.
#
# It is not a hypothetical shape. `Pool#return_holdings_to_the_account` re-points a destroyed
# envelope's categories at the account in bulk — that re-point is what keeps `Σ pools` conserved —
# so un-enveloping a category is exactly how a user reaches it, and `Category#buffer_funded?`'s own
# comment already documents the family of readers that part company there.
#
# THE LINE BETWEEN THE TWO POOLED ARMS IS `Budget#pool_must_not_be_an_account`, the model's own:
# a budget pool and a savings pool can both carry a rule and both hold money, so the envelope arm's
# sentence is true of both and they share it; an account can carry no rule, so it gets an arm that
# says what is actually true of it — the money comes out of the buffer, and an account IS the
# buffer (§7.1).
#
# See docs/superpowers/specs/2026-08-15-budgeting-ui-design.md §8.1.
class CategoryBudgetPresenter
  attr_reader :category, :today

  # `today` DEFAULTS TO Date.current AND IS NOT THE PAGE'S `selected_date`. The category page has a
  # period toggle and can be read for a month that is over; an envelope's balance is a fact about
  # NOW (§4.1 — the time word cannot be dropped), and rendering last March's row vocabulary beside
  # a live "View Savings Pool" button would be the page disagreeing with the pool screen it links
  # to. The spending figures above this block are the ones the toggle is for.
  def initialize(category:, today: Date.current)
    @category = category
    @today = today
  end

  # ---- Which state the block is in --------------------------------------------------------------

  # Up here rather than beside the arm that renders it, because #state reads it first.
  delegate :pool, to: :category

  # ONE READER FOR WHICH ARM RENDERS, because the block also stamps the state into the DOM for the
  # specs to scope by, and a `data-` attribute computed separately from the branch is free to name
  # an arm the page did not render — which would make a scoped assertion pass against the wrong
  # state and read as green. Both come from here.
  #
  # THE ACCOUNT TEST COMES FIRST and is asked of the POOL'S TYPE rather than of `pool_covered?`,
  # which is `expense? && pool_id.present?` and therefore says yes to an account. Read second it
  # would never be reached; read as `pool_covered?` at all it is the defect the class comment
  # describes.
  def state
    return :account_pointed if pool&.pool_type_account?
    return :pool_covered if pool.present?
    return :capped if capped?

    :uncapped
  end

  # The cap itself, so the view's branch and the link it renders read the same record.
  def cap = category.budget

  def capped? = cap.present?

  # ---- The pool-covered arm --------------------------------------------------------------------

  # ONE STATUS, so the state and the figure beside it cannot disagree — the same object the Budget
  # page's group header and Home's pool row are built from, which is what keeps all three screens
  # describing one envelope in one vocabulary on one afternoon.
  #
  # No `PoolBalanceLedger`: a ledger's whole point is answering for a SET of pools in grouped
  # queries, and this page renders exactly one. `PoolStatus` builds its own calculator for it.
  def status = @status ||= pool.status(today: today)

  # THE ROW VOCABULARY'S FOUR QUESTIONS, so this presenter can be handed straight to
  # `shared/_pool_status` exactly as `HomePresenter::Row` and `BudgetPagePresenter::Group` are.
  #
  # THIS IS THE POINT OF THAT PARTIAL, DEMONSTRATED. The pool card below the block is a NEW caller
  # of `pool_status_label` — the exact method 2c's whole-plan review caught two callers dropping a
  # suffix from — and it cannot repeat the defect, because it does not pass suffixes at all. It
  # passes an object, and an object either answers all four or raises on the first render.
  #
  # `balance_clause?` true and `due_marker?` false: the card prints no rules, so `· holds $X` is
  # the clause that adds something, exactly as on the Budget page. A date would be a rule's date
  # with nothing on the card saying which rule.
  delegate :needs_attention?, :period_closed?, to: :status
  def balance_clause? = true
  def due_marker? = false

  # THE POOL'S OWN MONEY, for the card's ACCOUNT arm — an account IS the buffer (§7.1), so what
  # the card owes the reader there is the cash sitting in it, the same quantity Home's account
  # header calls `buffer now`. Off the status this class already holds, never a second
  # `pool.calculator`: two objects for one balance is how two figures on one page disagree.
  #
  # The account arm reads no STATE, deliberately — `PoolStatus` would hand an account with a
  # target the `saving` state and word its buffer as progress toward a goal, which is the savings
  # chrome this rider exists to take off it.
  delegate :balance, to: :status

  # BOTH SUFFIXES, and this screen owes both for the reason `HomeHelper#pool_status_label`'s comment
  # gives: this block says how the envelope STANDS RIGHT NOW, so a clause here and not on Home is
  # two screens describing the same envelope differently. `period_closed?` rides on the status's own
  # calculator; this one is a question about the SCREEN's period, which a status cannot answer.
  #
  # One account — the envelope's — so the clock's one movement query is the whole cost. A pool with
  # no account answers false through the clock's own missing key rather than through a guard here.
  # `defined?` rather than `||=`, because the answer is false for most envelopes most of the time
  # and `||=` re-runs the clock's query on every call for exactly those — the memo would work only
  # where it was not needed.
  def changed_after_distributing?
    return @changed_after_distributing if defined?(@changed_after_distributing)

    @changed_after_distributing = DistributionClock
      .new(user: category.user, account_ids: [pool.account_id], today: today)
      .changed_after_distributing?(pool)
  end

  # ---- The two unfunded arms -------------------------------------------------------------------

  # WHETHER THE BUDGET PAGE IS CURRENTLY PROPOSING A RULE FOR THIS CATEGORY (§8.1's one addition to
  # the unchanged third state, and the account-pointed arm's only way out).
  #
  # `SuggestionEngine` itself, never a re-derivation of the four detectors' conditions: the pointer
  # exists to say that something is waiting on /budget, and a second reader of "is there" that
  # disagreed with the panel would send the user to an empty list — or, worse, stay silent over a
  # real one.
  #
  # `prefill[:category_id]` IS THE ENGINE'S OWN ANSWER to "which category would accepting this
  # move", the same key `BudgetPagePresenter#cap_for` reads, and on both asking arms it is
  # complete: `SuggestionEngine#envelope_half` sends a pool-less category AND an account-pointed
  # one down its CREATION branch ("an ACCOUNT is not reusable"), and that is the branch carrying
  # `category_id`. So every dated-bill and rate suggestion about either shape is keyed here. The
  # other two kinds are about pool-mode rules, which neither shape can own.
  #
  # THE COST, AND WHY IT IS PAID ONLY ON THESE TWO ARMS. The engine is 8 queries and ~14ms warm on
  # the demo's three-year history against a page that costs 14 queries and ~76ms. An enveloped or a
  # capped category never runs it. Gated at the reader rather than in the view so no second caller
  # can inherit the run without the state that justifies it.
  def suggestions
    return [] unless proposable?

    @suggestions ||= engine_suggestions.select { |suggestion| suggestion.prefill[:category_id] == category.id }
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
  # `Category#buffer_funded?` is the model's own reader for "this spending comes out of the buffer"
  # (no pool, or a pool that IS an account) and it is LITERALLY `SuggestionEngine#rates`' own
  # population, so the gate and the detector it gates on are the same reader rather than two that
  # can drift. `&& cap.blank?` is what keeps the pointer off the capped arm: `buffer_funded?` says
  # yes to a capped pool-less category — the engine does propose rates for those, which is why
  # `BudgetPagePresenter#cap_for` exists — but §8.1 puts the pointer in the no-cap state only, and
  # the capped arm already carries its own sentence about what a cap is.
  #
  # The three-way truth table, since the conjunction is doing real work:
  #
  #   no pool, no cap    → buffer_funded ✓, cap blank ✓ → asks   (§8.1's third state)
  #   no pool, capped    → buffer_funded ✓, cap set  ✗ → silent (§8.1's second state)
  #   account-pointed    → buffer_funded ✓, cap blank ✓ → asks   (a cap is forbidden here anyway)
  #   budget/savings pool→ buffer_funded ✗              → silent (the envelope arm)
  #
  # Asked of the model rather than of #state's symbol so an edit to the state names cannot widen
  # the gate, and written as one predicate rather than `state.in?([...])` so there is one place a
  # future arm has to be argued into.
  def proposable? = category.buffer_funded? && cap.blank?

  def engine_suggestions = SuggestionEngine.new(user: category.user, today: today).suggestions
end
