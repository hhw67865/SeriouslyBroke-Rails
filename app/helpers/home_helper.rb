# frozen_string_literal: true

# The row vocabulary of Home's bands: what a claim is, what is wrong with it, and when it is due.
module HomeHelper
  # What is wrong with a claim. The strip and the "This period" row print the same string about the
  # same rule inches apart, which is why it is one method.
  def claim_trouble_label(line)
    return "over by #{number_to_currency(line.over_by)}" if line.over?

    "overdue · was #{line.next_due_on.strftime("%b %-d")}"
  end

  # A stripe fill and a text colour per rule type. `fetch`, so a fourth type added to the enum with
  # no colour fails here rather than rendering a blank column.
  STRIPE_FILLS = { savings: "bg-savings", bill: "bg-brand-dark", usage: "bg-dusty-teal", choice: "bg-terracotta" }.freeze

  TYPE_TEXT = {
    savings: "text-savings", bill: "text-brand-dark", usage: "text-dusty-teal-dark", choice: "text-terracotta-dark"
  }.freeze

  def stripe_fill(line) = type_fill(line.stripe_type)

  # The same table asked of a bare type, for the places that colour a type with no row in hand.
  def type_fill(type) = STRIPE_FILLS.fetch(type.to_sym)

  def type_text_class(line) = TYPE_TEXT.fetch(line.stripe_type)

  # What the bar says in colour. The state is ClaimLine#bar_state; this is only its palette.
  BAR_FILLS = {
    full: "bg-status-success", over: "bg-status-danger", short: "bg-status-danger", normal: "bg-brand"
  }.freeze

  def bar_fill(line) = BAR_FILLS.fetch(line.bar_state)

  # `usage · a period` / `bill · every 12 months` / `choice · $5,000 by Jun 1, 2027` /
  # `bill · once, Dec 1`. The classification is Rule#cadence's; the words are this screen's.
  def shape_words(line) = "#{line.stripe_type} · #{shape_schedule_words(line)}"

  # A fund is its cadence plus one word: keeping what it doesn't spend is orthogonal to how often
  # the money arrives.
  def shape_schedule_words(line)
    words = cadence_words(line)

    line.fund? ? "#{words}, keeps" : words
  end

  def cadence_words(line)
    case line.rule.cadence
    when :per_period then "a period"
    when :every_n then "every #{line.rule.interval_months} months"
    else one_off_words(line)
    end
  end

  # A goal's date carries its year and a bill's does not: a goal's horizon is routinely years out,
  # where a bare "Jun 1" would read as this June.
  def one_off_words(line)
    return ["once", line.next_due_on&.strftime("%b %-d")].compact.join(", ") if line.rule.bill?

    [number_to_currency(line.target).to_s, line.next_due_on&.strftime("by %b %-d, %Y")].compact.join(" ")
  end

  # `$310.00 of $400.00` — one sentence for both shapes, off ClaimLine#filled and #denominator. A
  # fund aims at nothing, so its sentence stops early and names its noun instead.
  def figure_words(line)
    return "built up #{number_to_currency(line.filled)}#{" of #{number_to_currency(line.target)}" if line.target}" if line.fund?

    "#{number_to_currency(line.filled)} of #{number_to_currency(line.denominator)}"
  end

  # What the trouble strip says about an overspend. A fund's spending is measured against what it
  # HAD, not against this period's accrual, so the second figure changes with the shape.
  def claim_over_detail(line)
    spent = number_to_currency(line.spent)
    return "#{spent} spent, #{number_to_currency(line.built_up)} built up" if line.fund?

    "#{spent} spent of #{number_to_currency(line.accrued)}"
  end

  # `paid Aug 14` / `resets Oct 1` / `Sep 17 · ready` / `Apr 2 · +$41.67` / `Sep 20 · $40.00 short`.
  # The order of the arms is the order of the news: a finished one-off first, then a date gone by.
  def when_words(line)
    return finished_when_clause(line) if line.paid? || line.overdue?
    return line.resets_on && "resets #{line.resets_on.strftime("%b %-d")}" if line.rate?
    return fund_when_clause(line) if line.fund?

    [line.next_due_on&.strftime("%b %-d"), dated_when_clause(line)].compact.join(" · ").presence
  end

  # ClaimCalculator#overdue? asks !settled?, so the two arms can never both be true.
  def finished_when_clause(line)
    return ["paid", line.paid_on&.strftime("%b %-d")].compact.join(" ") if line.paid?

    "overdue · was #{line.next_due_on.strftime("%b %-d")}"
  end

  # A fund has no date to be ready or late for, so the one thing left to say is what it adds.
  def fund_when_clause(line)
    return "full at #{number_to_currency(line.target)}" if line.target && line.per_period.zero?
    return nil unless line.per_period.positive?

    "+#{number_to_currency(line.per_period)} a period"
  end

  # Nil where the share is not positive: a skipped period would otherwise advertise a `+$0.00`
  # contribution the rule is not making.
  def dated_when_clause(line)
    return "#{number_to_currency(line.fund_gap)} short" if line.short?
    return "ready" unless line.fund_short?

    line.per_period.positive? ? "+#{number_to_currency(line.per_period)}" : nil
  end

  # What an upcoming row says beside its amount.
  def upcoming_words(row)
    return "Ready — it's all there" if row.ready?
    return "#{number_to_currency(row.line.fund_gap)} short" if row.short?

    "#{number_to_currency(row.set_aside)} set aside · +#{number_to_currency(row.line.per_period)} a period"
  end

  # What the Budget page's rule row says beneath its this-period figure. A one-off bill has no
  # steady figure to compare against — it stops after its date — so it names the date instead.
  def steady_words(line)
    return "until #{line.next_due_on.strftime("%b %-d")}" if line.rule.cadence == :one_off
    return "full at #{number_to_currency(line.target)}" if line.fund? && line.target && line.per_period.zero?
    return "same every period" if line.per_period == line.rule.ask

    "#{number_to_currency(line.rule.ask)} a period once caught up"
  end

  # What a row calls the lane a rule covers. An item names itself; an item-less rule covers the
  # category's other items, so it is "everything else" beside item rules and "all of" it alone.
  def lane_words(line, rows)
    return line.rule.item.name if line.rule.item.present?

    rows.size > 1 ? "Everything else in #{line.category.name}" : "All of #{line.category.name}"
  end

  # What a row calls one of a category's rules. An item names itself; an item-less rule is named by
  # its shape, because the row already prints its amount and its date.
  def rule_label(rule)
    return rule.item.name if rule.item.present?

    case rule.cadence
    when :per_period then "Per period"
    when :one_off then "One-off"
    else "Every #{rule.interval_months} months"
    end
  end
end
