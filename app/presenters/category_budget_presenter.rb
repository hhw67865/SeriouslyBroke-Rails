# frozen_string_literal: true

# THE CATEGORIES PAGE'S BUDGET BLOCK, in the three states spec §8.1 gives it. Read-only — the cap
# form it links to owns the writes, and the envelope arm has nothing to write at all.
#
# The three states are DISJOINT AND EXHAUSTIVE for an expense category, and not by arrangement here:
# `Budget#category_must_not_have_pool` refuses a cap on a category that points at a pool, so
# "pool-covered" and "capped" cannot both be true, and "no pool, no cap" is the remainder. The view
# therefore branches once, in that order, with no fourth arm to render.
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

  # ---- Which of §8.1's three states ------------------------------------------------------------

  # ONE READER FOR WHICH ARM RENDERS, because the block also stamps the state into the DOM for the
  # specs to scope by, and a `data-` attribute computed separately from the branch is free to name
  # an arm the page did not render — which would make a scoped assertion pass against the wrong
  # state and read as green. Both come from here.
  def state
    return :pool_covered if category.pool_covered?
    return :capped if capped?

    :uncapped
  end

  # The cap itself, so the view's branch and the link it renders read the same record.
  def cap = category.budget

  def capped? = cap.present?

  # ---- The pool-covered arm --------------------------------------------------------------------

  delegate :pool, to: :category

  # ONE STATUS, so the state and the figure beside it cannot disagree — the same object the Budget
  # page's group header and Home's pool row are built from, which is what keeps all three screens
  # describing one envelope in one vocabulary on one afternoon.
  #
  # No `PoolBalanceLedger`: a ledger's whole point is answering for a SET of pools in grouped
  # queries, and this page renders exactly one. `PoolStatus` builds its own calculator for it.
  def status = @status ||= pool.status(today: today)

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

  # ---- The uncapped arm ------------------------------------------------------------------------

  # WHETHER THE BUDGET PAGE IS CURRENTLY PROPOSING A RULE FOR THIS CATEGORY (§8.1's one addition to
  # the unchanged third state).
  #
  # `SuggestionEngine` itself, never a re-derivation of the four detectors' conditions: the pointer
  # exists to say that something is waiting on /budget, and a second reader of "is there" that
  # disagreed with the panel would send the user to an empty list — or, worse, stay silent over a
  # real one.
  #
  # `prefill[:category_id]` IS THE ENGINE'S OWN ANSWER to "which category would accepting this
  # move", the same key `BudgetPagePresenter#cap_for` reads, and on this arm it is complete: a
  # category with no pool takes `#envelope_half`'s creation branch, which carries `category_id`, so
  # every dated-bill and rate suggestion about it is keyed here. The other two kinds are about
  # pool-mode rules, which a pool-less category cannot own.
  #
  # THE COST, AND WHY IT IS PAID ONLY HERE. The engine is 8 queries and ~14ms warm on the demo's
  # three-year history against a page that costs 14 queries and ~76ms, and it is asked ONLY on this
  # arm — a pool-covered or capped category never runs it. Gated at the reader rather than in the
  # view so no second caller can inherit the run without the state that justifies it.
  def suggestions
    return [] unless budgetable_and_uncapped?

    @suggestions ||= engine_suggestions.select { |suggestion| suggestion.prefill[:category_id] == category.id }
  end

  def suggested? = suggestions.any?

  # WHICH RUN ON /budget TO LAND IN. The engine's order is kind rank first (dated bills before
  # rates), so the first suggestion's kind is the most urgent thing waiting there, and
  # `suggestion_kind_anchor` is the same reader the panel's own index and headings use — one
  # spelling of the fragment, so this link cannot silently stop working.
  def first_suggestion_kind = suggestions.first&.kind

  private

  # THE SAME `:uncapped` #state ANSWERS, ASKED OF THE MODEL RATHER THAN OF THE SYMBOL, so the gate
  # that decides whether the engine runs cannot be widened by an edit to the state names. It is
  # also the only arm on which `prefill[:category_id]` is a complete answer (see #suggestions).
  def budgetable_and_uncapped? = category.budgetable? && cap.blank?

  def engine_suggestions = SuggestionEngine.new(user: category.user, today: today).suggestions
end
