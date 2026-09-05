# frozen_string_literal: true

# The row vocabulary of Home's bands. See the UI design spec §4.4.
#
# HomeHelper rather than ApplicationHelper (which the brief suggested) for two reasons: it
# is the helper Rails always mixes into home views whatever `include_all_helpers` is set to,
# which was the brief's whole objection to PoolsHelper; and ApplicationHelper is already at
# rubocop's Metrics/ModuleLength limit, so this vocabulary does not fit there without
# starting to delete other people's comments.
module HomeHelper
  # ** THE STATUS VOCABULARY IS GONE (computed-claims spec §6). ** `#pool_status_label`,
  # `#pool_state_label` and `#saving_label` read a `HoldingStatus` and printed its seven states —
  # `overdrawn`, `overdue`, `won't make it`, `behind`, `saving`, `left to spend`, `on track` — with
  # two suffixes, `· last period` and `— you changed a rule here after distributing`. Every one of
  # those sentences is about money that was MOVED into a category and what a distribution would do
  # to it next, and there are no movements on the purpose side any more (§5). The last screens that
  # spoke it — the categories page's holdings card and `shared/_holding_status` — were converted to
  # §3.4's claim vocabulary in this same commit, so the methods are callerless as well as
  # meaningless.
  #
  # WHAT SURVIVES OF THE SEVEN STATES is two facts about a claim rather than a state machine:
  # `ClaimCalculator#over?` (spent past what the rule allowed) and `#overdue?` (a date already
  # past), rendered by `#claim_trouble_label` below. `#pool_rule_label` is untouched — it names a
  # RULE, which is a question the change of model does not touch.

  # ── ** THE CLAIM VOCABULARY (computed-claims spec §3.4). ** ────────────────────────────────────
  #
  # `#period_row_clause`, `#quiet_period_marker` and `PERIOD_ROW_SILENT_STATES` ARE DELETED (Task 3),
  # and the deletion is that Home stopped asking their question rather than that nothing called them.
  # All three read a `HoldingStatus`, whose seven states describe what was MOVED into a category —
  # `left to spend`, `behind`, `· last period`, `— you changed a rule here after distributing`. There
  # are no movements on the purpose side any more (§5), so there is no "last period" money awaiting a
  # sweep, no distribution to have edited a rule after, and nothing "behind" that a transfer could
  # catch up. A claim is a FUNCTION, and the three things it can be is: under its rate, over it, or
  # accruing toward a date. Those are the three sentences below.
  #
  # THE STATUS VOCABULARY ITSELF IS NOT DELETED — the distribute, reallocation and category screens
  # still speak it, and Task 4 is what retires it with them. Home simply stopped.

  # THE FIGURE ON A "THIS PERIOD" ROW (§3.4): `spent of rate` for an envelope, `built up of target`
  # for a fund. ONE method for both because the two are the same shape said about different money,
  # and the caller must not choose the noun — a row that printed "spent" over a fund's running total
  # would be the money screen's oldest lie, that savings are money to spend.
  # ** THE UNCAPPED ARM IS DELETED WITH THE SHAPE (two-shapes spec §7). ** A building rule that named
  # no target had `ClaimCalculator#target` NIL — no ceiling — and an un-gated sentence printed
  # `$450.00 built up of ` with an empty figure after a dangling preposition. Every accruing rule has
  # a day and a figure now, so both halves of the "of" are always there.
  def claim_figure(line)
    return "#{number_to_currency(line.spent)} of #{number_to_currency(line.accrued)}" if line.rate?

    "#{number_to_currency(line.built_up)} built up of #{number_to_currency(line.target)}"
  end

  # THE SCHEDULE CLAUSE UNDER AN ACCRUING ROW (§3.4): `next due Mar 1 · $200.00 per period`.
  #
  # ** THE TENSE IS THE DATE'S OWN (fix round 1 — MED-1). ** A $600 bill due Aug 15, saved in full and
  # never paid, keeps its occurrence anchored where it was (§3.2) — so on Sep 3 this row printed
  # `next due Aug 15`, a date already gone under a word that promises a future one. `was due` is what
  # a past occurrence gets, and the side of `today` it falls on is read off `#overdue?` rather than
  # compared here: that predicate IS `next_due_on < today` (`ClaimCalculator#overdue?`), stated once,
  # so this clause and the trouble label above it cannot disagree about one date on one afternoon.
  #
  # ** WHAT DROPS AND WHAT SURVIVES (fix round 1 — MED-2, a comment that misstated its own code). **
  # It said "nil for a fund already full". It is not, and never was: a full fund's per-period SHARE is
  # zero, so that half of the clause drops and the DATE is printed alone (`was due Aug 15`) — which is
  # exactly the row a user with an unpaid bill needs. nil is returned for a RATE rule only, which has
  # neither half: use-it-or-lose-it accrues toward nothing and is due on no day. The view renders no
  # element at all where this is nil.
  #
  # ** THE BUILDING ARM IS DELETED WITH THE SHAPE (two-shapes spec §7). ** A building rule had no
  # date at all, so its clause was `+$300.00 per period` — money added every period for as long as
  # the rule lived — and `#building_schedule` was where that sentence lived. A goal names a day now,
  # so it takes the dated clause like every other accruing rule: `next due Jun 1 · $148.15 per
  # period`, which says the same thing with the deadline the share is derived from.
  def claim_schedule(line)
    return nil if line.rate?

    dated_schedule(line)
  end

  # THE DATED ROW'S: the occurrence, in the tense the date's own side of `today` gives it, and the
  # catch-up share where there is still one to ask for. Either half may drop; both dropping is the
  # settled one-off, which renders no element at all.
  def dated_schedule(line)
    [
      line.next_due_on && "#{line.overdue? ? "was due" : "next due"} #{line.next_due_on.strftime("%b %-d")}",
      line.per_period.positive? && "#{number_to_currency(line.per_period)} per period"
    ].select { |clause| clause.is_a?(String) }.join(" · ").presence
  end

  # WHAT IS WRONG WITH A CLAIM, IN THE TWO SHAPES §4 SAYS ARE WORTH A HUMAN. The strip and the "This
  # period" row print the SAME string about the same rule inches apart, which is why it is one method:
  # the two said it differently once already, under the status vocabulary this replaces.
  #
  # `over by` IS THE PRE-CLAMP FIGURE — `ClaimCalculator#over_by`, the excess that reduced `free`
  # directly (§3.1). The claim itself is zero in this state, so a figure taken from the claim would
  # print `over by $0.00` on every overspend.
  #
  # ** IT IS THE CALCULATOR'S SUBTRACTION AND NOT THIS METHOD'S (fix wave — LOW-2). ** It was spelled
  # `line.spent - line.accrued` here and `accrued_this_period - spent_this_period` in
  # `EntryImpactPresenter#pre_clamp_claim` — one figure, two derivations, on two screens that print
  # it about the same rule. All three §3.4 row objects carry `#over_by` off the one calculator now,
  # and `claim_calculator_spec` pins the two readings equal.
  #
  # `overdue · was Mar 1` KEEPS THE STATUS VOCABULARY'S OWN WORDING for the one state that survives
  # the change of readers unchanged in meaning: a date has passed and the money is not there.
  def claim_trouble_label(line)
    return "over by #{number_to_currency(line.over_by)}" if line.over?

    "overdue · was #{line.next_due_on.strftime("%b %-d")}"
  end

  # ── ** THE BLOCK ROW'S THREE PHRASES (two-shapes spec §3), ONE SPELLING EACH. ** ───────────────
  #
  # Home's category blocks say a rule in four parts: a stripe (its type), a name (its lane), WHAT
  # SHAPE it is, WHAT IT HAS, and WHEN. The last three are these, and they are here rather than in
  # `home/_this_period.html.erb` because Task 3's Budget rows and Task 4's rule-form preview say the
  # same three about the same rules — a second spelling is how one screen comes to describe a rule
  # differently from the screen a click away, which is the defect `#claim_trouble_label`'s own header
  # records having already happened once.
  #
  # ** WHAT THEY DID NOT REPLACE, AND WHY THE BRIEF'S "NAME DELETIONS" ARE A PUSHBACK. ** The brief
  # has `#claim_figure` and `#claim_schedule` folding into these two and their names deleted. They
  # cannot be deleted here: both are read by `budget_page/_rule_row.html.erb` and by
  # `categories/_partials/show/_holdings_card.html.erb`, and BOTH of those screens are out of this
  # task's scope — the Budget page is Task 3's and the categories page is out of scope for the whole
  # plan (spec §8: "they keep their current shape"). Deleting the names would have meant either
  # breaking two screens or changing their copy without a ruling, since the sentences genuinely
  # differ: this section says `$450.00 of $1,200.00` where those rows say `$450.00 built up of
  # $1,200.00`. So the two old methods stay, unchanged, with two callers each, and the fold happens
  # in Task 3 when the rows that read them are rebuilt.

  # ** THE THREE RULE-TYPE COLOURS, ONE TABLE (two-shapes spec §3). ** A stripe fill and a text
  # colour per type, `fetch`ed for `Budget::TYPE_RANK`'s own reason: a fourth type added to the enum
  # without a colour is a row rendering with no stripe at all, which is invisible until someone
  # notices a blank column. The two accents are DARKER as text than as fills and the measurements are
  # in `custom.css` beside the tokens — the fills are decorative and clear 3:1, the words are text
  # and have to clear 4.5:1.
  STRIPE_FILLS = { bill: "bg-brand-darker", usage: "bg-dusty-teal", choice: "bg-terracotta" }.freeze

  TYPE_TEXT = {
    bill: "text-brand-dark", usage: "text-dusty-teal-dark", choice: "text-terracotta-dark"
  }.freeze

  def stripe_fill(line) = STRIPE_FILLS.fetch(line.stripe_type)

  def type_text_class(line) = TYPE_TEXT.fetch(line.stripe_type)

  # WHAT THE BAR SAYS IN COLOUR (§3: "green full, red over/short"). The state is
  # `ClaimLine#bar_state` — one classification, on the row — and this is only its palette, so a
  # screen cannot decide a row is over while another decides it is full.
  BAR_FILLS = {
    full: "bg-status-success", over: "bg-status-danger", short: "bg-status-danger", normal: "bg-brand-dark"
  }.freeze

  def bar_fill(line) = BAR_FILLS.fetch(line.bar_state)

  # `usage · a period` / `bill · every 12 months` / `choice · $5,000 by Jun 1, 2027` /
  # `bill · once, Dec 1`.
  #
  # THE CLASSIFICATION IS `Budget#cadence`'s, THE WORDS ARE THIS SCREEN'S — the split every rule-shape
  # reader in this app keeps (`#pool_rule_label` names a rule, `BudgetPageHelper#budget_rule_basis`
  # says what an amount is per). A fifth cascade over `basis`/`interval_months`/`anchor_date` here
  # would be a fifth chance to classify one rule two ways.
  def shape_words(line) = "#{line.stripe_type} · #{shape_schedule_words(line)}"

  # ** A ONE-OFF SPLITS ON ITS TYPE, AND THAT IS NOT `Budget.saving_toward_a_date` (LOW-7's clause
  # asked of a different question). ** That scope answers "which ONE rule is this category's savings
  # row" and needs `item_id IS NULL` to stay single-valued per category; this asks "what does this
  # rule say about itself", where the lane it names changes nothing. What is left of the scope once
  # the `:one_off` branch has already established the anchor and the absent interval is the type
  # alone: a bill is a thing to PAY on a day ("once, Dec 1"), and anything else with a day is a
  # figure being SAVED toward ("$5,000 by Jun 1, 2027").
  #
  # THE GOAL'S DATE CARRIES ITS YEAR AND THE BILL'S DOES NOT, deliberately: a goal's horizon is
  # routinely years out and `Jun 1` alone would read as this June, while a one-time bill inside the
  # next few months is the shape "Dec 1" is unambiguous for.
  def shape_schedule_words(line)
    case line.rule.cadence
    when :per_period then "a period"
    when :monthly then "every month"
    when :every_n then "every #{line.rule.interval_months} months"
    else
      if line.rule.bill?
        "once, #{line.next_due_on.strftime("%b %-d")}"
      else
        "#{number_to_currency(line.target)} by #{line.next_due_on.strftime("%b %-d, %Y")}"
      end
    end
  end

  # `$310.00 of $400.00` — spending against this period's rate for a rate rule, the running total
  # against the target for a dated one. ONE sentence for both shapes, because `ClaimLine#filled` and
  # `#denominator` are the pair that makes them one: the caller must not choose the noun, and a row
  # that printed "spent" over a target's running total would be the money screen's oldest lie.
  def figure_words(line) = "#{number_to_currency(line.filled)} of #{number_to_currency(line.denominator)}"

  # `resets Oct 1` / `Sep 17 · ready` / `Apr 2 · +$41.67` / `Sep 20 · $40.00 short` /
  # `overdue · was Aug 15`.
  #
  # THE ORDER OF THE ARMS IS THE ORDER OF THE NEWS. A date already gone with the money missing comes
  # first whatever else is true of the row (and keeps `#claim_trouble_label`'s exact wording, so the
  # strip above and the row below say one string about one rule); then the money missing on a day
  # that is HERE (`ClaimLine#short?`); then a rule that has arrived; then one still accruing.
  #
  # THE LAST ARM DROPS TO THE BARE DATE WHERE THE SHARE IS ZERO. A one-time bill whose money has
  # already been spent asks for nothing more (`ClaimCalculator#planned_for`'s settled gate), so
  # `+$0.00` would be a rule advertising a contribution it is not making.
  def when_words(line)
    return "overdue · was #{line.next_due_on.strftime("%b %-d")}" if line.overdue?
    return line.resets_on && "resets #{line.resets_on.strftime("%b %-d")}" if line.rate?

    [line.next_due_on.strftime("%b %-d"), dated_when_clause(line)].compact.join(" · ")
  end

  def dated_when_clause(line)
    return "#{number_to_currency(line.fund_gap)} short" if line.short?
    return "ready" unless line.fund_short?

    line.per_period.positive? ? "+#{number_to_currency(line.per_period)}" : nil
  end

  # ** THE PACE, SAID ONCE FOR BOTH PANELS (§3 and §4). ** The runway's pace line and the shortfall
  # strip's remedy are the same sentence about the same figure — the strip only ever renders the
  # second arm, because it only renders while `free` is below zero — and they were written twice in
  # two views for one wave, which is how two panels on one screen come to name different amounts.
  # `HomePresenter::Pace` decides which arm; this says it.
  def pace_words(pace)
    return nil if pace.nil?
    return "#{number_to_currency(pace.amount)} a day is fine for the rest of the period." if pace.fine?

    "Spending #{number_to_currency(pace.amount)} a day less for the rest of this period lands it at zero."
  end

  # What an expanded row calls one of a pool's rules.
  #
  # An item names itself. An item-less rule used to render the literal word "Rule", which on
  # screen reads as missing data rather than as information — so it is named by its SHAPE
  # instead, because the row already prints its amount and its date on the other side and how
  # often it comes round is the only thing the line was still missing.
  #
  # A LOOKUP ON `Budget#cadence` below the item branch, not a predicate cascade of its own: this
  # and `BudgetPageHelper#budget_rule_basis` used to hold the same four-branch classification in
  # the same hazard-ordered sequence. The classification is the record's, the wording is this
  # screen's — Home NAMES a rule, the Budget page says what an amount is per.
  def pool_rule_label(budget)
    return budget.item.name if budget.item.present?

    case budget.cadence
    when :per_period then "Per period"
    when :monthly then "Monthly"
    when :one_off then "One-off"
    else "Every #{budget.interval_months} months"
    end
  end

  # ── `#saving_label` IS DELETED (rules-own-the-budget spec §7), and it was the last of the status
  # vocabulary standing. It read a `HoldingStatus` — a class deleted with the movements it described
  # — and printed the accumulation state of MOVED money; `spec/helpers/home_helper_spec.rb`'s
  # tombstone had already listed it among the twelve, so what survived was the method and not its
  # caller. `#claim_figure` above is what says a fund's running total now, and it says it off a
  # claim.

  # ── `#fix_button_label` AND `#fix_gap_sentence` ARE DELETED (computed-claims Task 3), with the
  # whole fix apparatus they labelled. A "fix" was an ALLOCATION — money moved from one category, or
  # from AVAILABLE, into the one that was short — and §5 leaves the purpose side with no movements at
  # all. There is nothing left to take money FROM, because nothing holds any: a claim is computed, and
  # the only things that change one are a rule, an adjustment (§3.3) or spending less. The strip says
  # so and its one door is the Budget page. `/allocations/new` and the sentences these labelled are
  # still alive for the reallocation screen until Task 4 deletes it.

  # ── `#pool_problem_label` IS DELETED (answers-first Task 2), and the property it existed for is
  # not lost — it became structural. It forced `period_closed:` off the status so that Home's
  # attention band could not omit the suffix the categories band printed inches below; the strip
  # that replaced that band renders `shared/_holding_status` instead, which threads BOTH suffixes off
  # ONE row object (`HomePresenter::Row`). A caller no longer chooses which suffixes to pass, it
  # chooses which OBJECT to pass, and an object missing an answer raises at render. That partial's
  # own header carried this method as its ONE documented exception; the exception is gone with it.
end
