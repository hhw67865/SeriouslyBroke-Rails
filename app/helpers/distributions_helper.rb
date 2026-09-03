# frozen_string_literal: true

# The distribution screen's row copy. See the UI design spec §5.
module DistributionsHelper
  # The states whose label already prints a date of its own — HoldingStatus picks the rule that PUT
  # the category in that state, which is not necessarily the earliest-due one this row's schedule
  # clause describes. Named here rather than string-testing the label for a date, which would be
  # an assertion about a string this module does not own.
  #
  # TWO, not three. `:behind` was in this list on the reasoning that the design spec's §4.4 row
  # vocabulary writes it as `behind $385 · Mar 1` — but `HomeHelper#pool_state_label` prints
  # `behind $385` and no date at all, so listing it suppressed the schedule clause on a row that
  # then had no date anywhere on it: `behind $1,022.22`, about a bill with a due date. Measured
  # on the dated-bill system example, which expected the date and found the bare label.
  DATED_STATES = [:overdue, :wont_make_it].freeze

  # What a waterfall row says about the envelope itself: the app's existing row vocabulary
  # (spec §4.4, `HomeHelper#pool_status_label`), plus the schedule behind the ask.
  #
  # ONE date per row, never two. `behind $385 · Mar 1 · due Feb 14 · 2 periods left` is two
  # different bills' dates side by side, and there is no reading of that row that recovers
  # which is which — so where the state already carries a date, the state's date wins and the
  # schedule clause stays off.
  #
  # The ` · last period` suffix rides along from `pool_status_label`, and it is the clause this
  # screen most needs: it marks exactly the envelopes whose leftover the sources breakdown is
  # about to sweep back.
  def distribution_line_detail(line)
    label = pool_status_label(line.status, period_closed: line.period_closed)
    return label if DATED_STATES.include?(line.status.state) || !line.scheduled?

    "#{label} · due #{line.due_on.strftime("%b %-d")} · #{pluralize(line.periods_left, "period")} left"
  end

  # What the row proposes to put in, on the right-hand side. `$315.00 of $400.00` only where
  # the two differ: `$400.00 of $400.00` on a fully funded row is noise, and it is the row that
  # is NOT fully funded that has to stand out on a screen whose job is showing where the money
  # ran out.
  def distribution_line_amount(line)
    return number_to_currency(line.funded) unless line.short?

    "#{number_to_currency(line.funded)} of #{number_to_currency(line.needed)}"
  end

  # WHY THE FULL TABLE IS OPEN on a period that is not short. Three causes, and they are not
  # interchangeable:
  #
  #   something is genuinely wrong below (an overdue bill, an envelope that will not make its
  #   date) — the case the two-density design exists for;
  #
  #   the user ASKED to see it, on a period where nothing needs them at all. "But something below
  #   still needs you" is then a small lie that sends someone hunting for a problem that is not
  #   there — and it was the only copy this branch had until a fourth demo account made the
  #   combination reachable;
  #
  #   the user's own edit made the period all clear, so the table stays open to hold the boxes.
  #
  # `needs_attention?` and `expand_requested?` already distinguish all three, so this is a branch
  # and not new state.
  def distribution_waterfall_reason(presenter)
    if presenter.needs_attention?
      return "Every envelope gets what it asked for, but something below still needs you — " \
             "so the whole split is shown rather than a single line."
    end
    return "Every envelope gets what it asked for. You asked to see the whole split, so here it is." if
      presenter.expand_requested?

    "Every envelope gets what it asked for — your edits are shown below."
  end

  # What goes IN the box: the user's own figure, and NOTHING at all on a row they have not
  # edited. An empty box is what tells AllocationCalculator this row still wants its rule's ask,
  # and it is the only thing that lets money freed above it cascade down — a box carrying the
  # proposal would submit that figure back and pin the row where it was.
  #
  # `line.needed`, not `line.funded`: it is what the user typed, before available clamped it.
  # Rendering the clamped figure would silently rewrite a $350 edit as $185 the moment the page
  # came back, and the user would never see that their number had been changed for them.
  def distribution_override_value(line)
    return nil unless line.overridden?

    number_with_precision(line.needed, precision: 2, delimiter: "")
  end

  # What the box SHOWS when it is empty: what this row is getting if it is left alone. Plain
  # digits with two decimals and no currency symbol and no thousands delimiter, because a
  # `number_field` holding "$1,419.00" is a field the browser refuses to read back — it reports
  # empty, and an empty box means something specific here.
  def distribution_override_placeholder(line)
    number_with_precision(line.funded, precision: 2, delimiter: "")
  end

  # How many recipients get named before a sentence stops being something a person would say
  # aloud. Past three, the two that moved most and a total for the rest — never "and 1 other",
  # which is longer than the name it replaces.
  NAMED_RECIPIENTS = 3

  # WHERE THE MONEY WENT, on the row that moved it. The companion to the consequence line: that
  # one is about a later period, this one is about the split on the screen right now.
  #
  # It exists because the waterfall re-runs beneath an edit, so envelopes the user never touched
  # change their figures. A screen that moves money without saying where is the one thing that
  # would make the cascade worse than no cascade.
  def distribution_redirect_sentence(redirect)
    return distribution_redirect_shift(redirect) if redirect.shifted?
    return distribution_redirect_buffer_only(redirect) if redirect.buffer_only?

    "#{distribution_redirect_lead(redirect)}: #{distribution_redirect_destinations(redirect).to_sentence}."
  end

  # BOTH ENDS NAMED, for edits that cancel on net. Neither "freed" nor "took" is true — nothing
  # left the group — so the sentence states what changed hands and where it came from as well as
  # where it went. Without it the screen said nothing at all on the one occasion a user had just
  # reshuffled their budget.
  #
  # The one-to-one shape gets the short reading, because it is the shape this mode is nearly
  # always in and "$300.00 from Groceries and $300.00 to Rent" reads as $600. Anything wider gets
  # one flat list where every part carries its own preposition and its own figure: each side sums
  # to the lead by construction, so nothing here can be added to anything else.
  def distribution_redirect_shift(redirect)
    total = number_to_currency(redirect.total)
    return "Your edits move #{total}: #{distribution_redirect_pair(redirect)}." if
      redirect.sources.one? && redirect.recipients.one?

    parts = redirect.sources.map { |party, amount| "#{number_to_currency(amount)} from #{distribution_party(party)}" }
    parts += redirect.recipients.map { |party, amount| "#{number_to_currency(amount)} to #{distribution_party(party)}" }
    "Your edits move #{total}: #{parts.to_sentence}."
  end

  def distribution_redirect_pair(redirect)
    source, amount = redirect.sources.first

    "#{number_to_currency(amount)} from #{distribution_party(source)} " \
      "to #{distribution_party(redirect.recipients.first.first)}"
  end

  # A `nil` category is AVAILABLE. It is a party to a shift like any other — money can land there or
  # come out of it — rather than the residual it is in the other two modes.
  #
  # `ReallocationPresenter::ROOT.name` and not a string of its own: the app has ONE name for the
  # money no category holds, and `AllocationsHelper#allocation_party_name` already prints it in the
  # confirmation the user reads one screen later. (It was "your buffer" until the answers-first Home
  # spec §3 retired the word.)
  def distribution_party(category) = category&.name || ReallocationPresenter::ROOT.name

  # "That" for one row's own edit, "Your edits" for the aggregate above the table. The subject is
  # the only thing that changes: the arithmetic underneath is the same subtraction, taken against
  # a different baseline (see DistributionPresenter::Redirect).
  def distribution_redirect_lead(redirect)
    subject = redirect.aggregate? ? "Your edits" : "That"
    return "#{subject} free#{"s" unless redirect.aggregate?} #{number_to_currency(redirect.moved)}" if redirect.freed?

    "#{subject} take#{"s" unless redirect.aggregate?} #{number_to_currency(-redirect.moved)} more"
  end

  # The answer said as an answer rather than as a list of one. "$300.00 to Available" restates
  # the lead and leaves out the half that matters — that nothing below was waiting for it — and
  # a user told only the first half concludes the money vanished.
  #
  # ONE REGISTER FOR THE PARTY, and it is the proper noun. Its sibling above prints "$300.00 to
  # Available" through #distribution_party, and Available is a place with a balance on this screen
  # — the sources table's own row, the waterfall's last row, "Available is $200.00 in the red". A
  # sentence that lowercases it describes a STATE instead of naming where the money went, which is
  # the ambiguity the two-ledger design removed. (Home's confirmation flash keeps the lowercase
  # adjective: spec §3 lets only Distribute and Budget name the mechanic's party.)
  def distribution_redirect_buffer_only(redirect)
    return "#{distribution_redirect_lead(redirect)}, out of Available." unless redirect.freed?

    subject = redirect.aggregate? ? "them" : "it"
    "#{distribution_redirect_lead(redirect)}, and nothing below #{subject} was waiting — " \
      "it stays in Available."
  end

  # Available is always named last and never truncated: it is where the money stops, and a
  # sentence that trails off before reaching it has not answered the question.
  #
  # Every figure here carries its own number, and it can: there is exactly ONE of these sentences
  # on the screen at a time (one row's, or one aggregate), computed against one baseline, so the
  # parts sum to the lead and nothing on the screen can be added to anything else.
  def distribution_redirect_destinations(redirect)
    named, rest = distribution_redirect_split(redirect.recipients)
    preposition = redirect.freed? ? "to" : "from"

    parts = named.map { |category, amount| "#{number_to_currency(amount)} #{preposition} #{category.name}" }
    parts << "#{number_to_currency(rest.sum(0.to_d, &:last))} across #{pluralize(rest.size, "other")}" if rest.any?
    parts << "#{number_to_currency(redirect.buffer)} #{preposition} #{ReallocationPresenter::ROOT.name}" if redirect.buffer?
    parts
  end

  # Name them all up to the limit, otherwise the two that moved most and a summary for the rest.
  def distribution_redirect_split(recipients)
    return [recipients, []] if recipients.size <= NAMED_RECIPIENTS

    [recipients.first(2), recipients.drop(2)]
  end

  # THE SENTENCE THIS TASK EXISTS FOR: what an override costs the user later, naming the
  # mechanism and not only the number.
  #
  # Two shapes, because the two situations are different problems. The ordinary one is a trade —
  # money moved onto a later period, and that later period says how much more it will want. The
  # other is an envelope that can no longer make its date, and there the next period's figure is
  # beside the point: it is a period that falls after the bill was due. That one speaks in the
  # app's existing row vocabulary (spec §4.4) rather than in a sentence of its own, because it
  # is an existing state and not a new one.
  def distribution_consequence_sentence(consequence)
    return distribution_unrecoverable_sentence(consequence) if consequence.unrecoverable?

    "#{distribution_moving_clause(consequence)} #{distribution_next_period_clause(consequence)}"
  end

  # Which direction the money went. Both directions are real: a user who types a bigger figure
  # than the proposal is covering a later period early, and telling them they are "moving
  # -$300.00 onto your next period" is a sentence with no reading.
  def distribution_moving_clause(consequence)
    return "You're moving #{number_to_currency(consequence.moving)} onto your next period." if consequence.moving_later?

    "You're covering #{number_to_currency(-consequence.moving)} early."
  end

  # "Feb 20 will need $800.00 instead of $500.00, the last period before Mar 1."
  #
  # The trailing clause is what makes the number mean something — $800 instead of $500 is
  # alarming or routine depending entirely on whether anything comes after it — and it is
  # printed only when the projection actually says so (Consequence#last_period?).
  def distribution_next_period_clause(consequence)
    figures = "#{consequence.opens_on.strftime("%b %-d")} will need " \
              "#{number_to_currency(consequence.next_ask)} instead of #{number_to_currency(consequence.baseline_ask)}"
    return "#{figures}." unless consequence.last_period?

    "#{figures}, the last period before #{consequence.due_on.strftime("%b %-d")}."
  end

  # The red case, in the state the app already has for it. `pool_status_label` is HomeHelper's
  # one row vocabulary and the Standing is exactly what it consumes, so this row reads
  # "won't make it · Mar 1" in the same words and the same red as everywhere else in the app.
  # No "you're moving it onto your next period" clause here, and its absence is the point: there
  # is no next period that can help, which is the whole of what this state means. Naming one
  # would be the reassuring half of a sentence whose other half is that the bill cannot be paid.
  def distribution_unrecoverable_sentence(consequence)
    "#{pool_status_label(consequence.standing)} — the " \
      "#{number_to_currency(consequence.standing.amount)} still missing has no period left to " \
      "arrive in, so nothing after this distribution can fix it."
  end
end
