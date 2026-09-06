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

  # ** `#claim_figure`, `#claim_schedule` AND `#dated_schedule` ARE DELETED (this task's carry (b)).
  # ** They were the SECOND spelling of a row's figure and a row's date: `#claim_figure` said
  # `$450.00 built up of $1,200.00` where `#figure_words` says `$450.00 of $1,200.00`, and
  # `#claim_schedule` said `next due Mar 1 · $200.00 per period` where `#when_words` says
  # `Mar 1 · +$200.00`. Two helpers, one fact, and the split was not a design: Task 2 kept them alive
  # by ruling because their two readers — `budget_page/_rule_row` and the categories holdings card —
  # were outside that task's scope, and named this task as the fold. Both readers are converted in
  # this commit and both now print the same sentence Home prints about the same rule.
  #
  # WHAT SURVIVES IS `#claim_trouble_label` below, which is a different question (what is WRONG with
  # a claim, in the two shapes §4 says are worth a human) and is rendered by the trouble strip, the
  # categories card and nothing else.

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

  def stripe_fill(line) = type_fill(line.stripe_type)

  # THE SAME TABLE ASKED OF A BARE TYPE, for the two places on the Budget page that colour a type
  # with no row in hand: the list's dots (one per rule) and the tiles' segmented bar (one band per
  # kind). `fetch` for `#stripe_fill`'s own reason — a fourth type without a colour is a dot nobody
  # can see rather than a failure anybody notices.
  def type_fill(type) = STRIPE_FILLS.fetch(type.to_sym)

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
  #
  # ** NIL-SAFE ON THE DATE (this task's carry (a)). ** Every arm below that names a day drops the
  # day rather than raising where there is none: `once` and `$5,000.00` are true sentences about a
  # rule, `undefined method 'strftime' for nil` is a 500 on a money screen. The shape cannot be
  # `:one_off` without an anchor today — `Budget#cadence` reads the column — so this is a guard and
  # not a branch the data reaches; it is here because these words are now rendered by THREE screens
  # over rows built by three presenters, and the one that raised would be whichever built a row for
  # a rule mid-edit.
  # ** A FUND IS ITS CADENCE PLUS ONE WORD (two-shapes spec §12): `usage · a period, keeps`. ** The
  # suffix rather than a fourth cadence, because "keeps what it doesn't spend" is orthogonal to how
  # often the money arrives — a fund is a per-period rule in every other sentence the app says about
  # it (`Budget#cadence` is `:per_period`, `CadenceChange` scales it, `#steady_ask` takes its amount
  # verbatim) — and a `monthly`-basis fund would otherwise have to choose between saying its cadence
  # and saying that it keeps.
  def shape_schedule_words(line)
    words = cadence_words(line)

    line.fund? ? "#{words}, keeps" : words
  end

  def cadence_words(line)
    case line.rule.cadence
    when :per_period then "a period"
    when :monthly then "every month"
    when :every_n then "every #{line.rule.interval_months} months"
    else one_off_words(line)
    end
  end

  def one_off_words(line)
    return ["once", line.next_due_on&.strftime("%b %-d")].compact.join(", ") if line.rule.bill?

    [number_to_currency(line.target).to_s, line.next_due_on&.strftime("by %b %-d, %Y")].compact.join(" ")
  end

  # `$310.00 of $400.00` — spending against this period's rate for a rate rule, the running total
  # against the target for a dated one. ONE sentence for both shapes, because `ClaimLine#filled` and
  # `#denominator` are the pair that makes them one: the caller must not choose the noun, and a row
  # that printed "spent" over a target's running total would be the money screen's oldest lie.
  # ** A FUND HAS NO "of", BECAUSE IT IS AIMING AT NOTHING (§12). ** `built up $806.00` and there the
  # sentence stops: a rule that keeps what it doesn't spend has no target, so `of $0.00` would be a
  # denominator invented for the sake of the sentence's shape — and `$806.00 of $0.00` reads as a
  # rule $806.00 over its limit, which is the opposite of what a fund doing its job looks like. The
  # noun is stated here for the same reason the two-shape sentence refuses one: with no second figure
  # beside it, a bare `$806.00` in a row that prints spending everywhere else would read as spending.
  def figure_words(line)
    return "built up #{number_to_currency(line.filled)}" if line.fund?

    "#{number_to_currency(line.filled)} of #{number_to_currency(line.denominator)}"
  end

  # `paid Aug 14` / `resets Oct 1` / `Sep 17 · ready` / `Apr 2 · +$41.67` / `Sep 20 · $40.00 short` /
  # `overdue · was Aug 15`.
  #
  # THE ORDER OF THE ARMS IS THE ORDER OF THE NEWS. A one-off that is DONE comes first, because
  # nothing else the row could say about it is true any more; then a date already gone with the money
  # missing (which keeps `#claim_trouble_label`'s exact wording, so the strip above and the row below
  # say one string about one rule); then the money missing on a day that is HERE (`ClaimLine#short?`);
  # then a rule that has arrived; then one still accruing.
  #
  # ** THE PAID ARM IS THIS TASK'S CARRY (a). ** A one-time bill's occurrence never rolls, so before
  # its date a paid rule read `Sep 20 · $600.00 short` and after it `overdue · was Sep 20` — the two
  # worst sentences the vocabulary has, about a bill that had been paid. `ClaimLine#paid?` is the
  # fulfilment and `#paid_on` is the day the spending reached the target, which
  # `ClaimCalculator#settled_on` reads off rows the walk had already summed — so the row names the
  # day rather than saying a bare "paid", at no cost. The arm degrades to "paid" alone where the
  # settling day cannot be named.
  #
  # THE ACCRUING ARM DROPS TO THE BARE DATE WHERE THE SHARE IS ZERO. A rule asking for nothing more
  # would otherwise advertise a `+$0.00` contribution it is not making.
  # ** A FUND'S CLAUSE IS WHAT IT ADDS, NOT WHEN IT ENDS (§12): `+$60.00 a period`. ** It has no
  # date to be ready or late for and no boundary to reset on, so the one thing left to say about it
  # is that it keeps growing and by how much. The unit is spelled out — `+$41.67` alone is the DATED
  # arm's clause, where the date beside it says what the period is — and nothing here can say it.
  #
  # NIL WHERE THE SHARE IS NOT POSITIVE, on the accruing arm's own rule: a skipped period would
  # otherwise advertise a `+$0.00` contribution the rule is not making. (`#per_period` is the
  # PRE-adjustment plan, so this is the rule's standing contribution rather than this period's
  # accrual — the same figure the dated arm prints.)
  def when_words(line)
    return finished_when_clause(line) if line.paid? || line.overdue?
    return line.resets_on && "resets #{line.resets_on.strftime("%b %-d")}" if line.rate?
    return fund_when_clause(line) if line.fund?

    [line.next_due_on&.strftime("%b %-d"), dated_when_clause(line)].compact.join(" · ").presence
  end

  # THE TWO ARMS ABOUT A DAY THAT HAS ALREADY DECIDED SOMETHING, split out to keep `#when_words`
  # readable now that it answers four shapes. `#overdue?` is false of a settled rule
  # (`ClaimCalculator#overdue?` asks `!settled?`), so the two can never both be true and the order
  # here is the same order the cascade above read them in.
  def finished_when_clause(line)
    return ["paid", line.paid_on&.strftime("%b %-d")].compact.join(" ") if line.paid?

    "overdue · was #{line.next_due_on.strftime("%b %-d")}"
  end

  def fund_when_clause(line)
    return nil unless line.per_period.positive?

    "+#{number_to_currency(line.per_period)} a period"
  end

  def dated_when_clause(line)
    return "#{number_to_currency(line.fund_gap)} short" if line.short?
    return "ready" unless line.fund_short?

    line.per_period.positive? ? "+#{number_to_currency(line.per_period)}" : nil
  end

  # ** WHAT A RUNWAY TICK SAYS BESIDE ITS DOT — the name, and whether the money is there. ** Said in
  # ONE place because the runway says it in TWO: on the rail at full width, and down in the pace
  # block at 375 where two labels three days apart would overlap. The same tick, the same words, so
  # the two spellings of one screen cannot disagree about whether a bill is ready.
  #
  # NO DATE IN IT, and that is the panel's own point: a tick's PLACE on the ruler is its day, which
  # is the one thing a list of dated rows could not say. `#when_words` still carries the date for the
  # rows in "This period", which have no ruler to sit on.
  def runway_tick_words(tick)
    state = tick.short? ? "#{number_to_currency(tick.gap)} short" : "ready"

    "#{tick.label} · #{state}"
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
