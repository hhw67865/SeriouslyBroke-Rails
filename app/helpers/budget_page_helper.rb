# frozen_string_literal: true

# The Budget page's row copy, and the rule form's.
module BudgetPageHelper
  # The overview's line is a heading over a SUM of rules, so `bill` pluralises there; the label on
  # one row names ONE rule and does not. `fetch`, so a fourth type fails loudly.
  TYPE_HEADINGS = { "bill" => "Bills", "usage" => "Usage", "choice" => "Choice" }.freeze

  def rule_type_heading(type) = TYPE_HEADINGS.fetch(type.to_s)

  # What a rule is called. The item it pays is the truest name; where there is none the rule is the
  # category's own, and the owner is the subject.
  def rule_name(rule)
    rule.item&.name || rule.category&.name
  end

  # What an amount is per — a lookup on Rule#cadence rather than a predicate cascade of its own.
  def rule_basis(rule)
    case rule.cadence
    when :per_period then "/ period"
    when :one_off then "once"
    else "every #{rule.interval_months} months"
    end
  end

  # The same fact said in a sentence rather than beside a figure: `/ period` reads as a unit against
  # a figure and as stranded notation in prose.
  def rule_basis_phrase(rule) = rule.cadence == :per_period ? "per period" : rule_basis(rule)

  # The list the reorder endpoint takes, with one category moved one place. The WHOLE list goes on
  # the wire, because the endpoint's contract is an order and not an instruction.
  def reordered_category_ids(groups, group, offset)
    ids = groups.map { |candidate| candidate.category.id }
    index = ids.index(group.category.id)
    target = index + offset
    return ids unless target.between?(0, ids.size - 1)

    ids.insert(target, ids.delete_at(index))
  end

  # Whether this category is already as far as `offset` would take it.
  def reorder_edge?(groups, group, offset)
    index = groups.index(group)

    offset.negative? ? index.zero? : index == groups.size - 1
  end

  # What the amount field is an amount of.
  def rule_amount_hint(rule)
    "What this rule asks for #{rule_basis_phrase(rule)}."
  end

  # One category is open at a time, so the link on a CLOSED row opens it and the link on the OPEN
  # one closes the list. Without JavaScript these two hrefs are the whole mechanism.
  def category_toggle_path(row) = row.open? ? budget_page_path : budget_page_path(open: row.category.id)

  def category_toggle_label(row) = "#{row.open? ? "Hide" : "Show"} #{row.category.name}"

  # "every month" / "every 6 months", said of an interval rather than of a saved rule.
  def interval_label(months) = months == 1 ? "every month" : "every #{months} months"

  # The preview's date always carries its year, deliberately unlike the rows': it is read seconds
  # after the user typed it, where a mistyped year is the error no other figure reveals.
  PREVIEW_DATE = "%b %-d, %Y"

  def rule_preview_date(date) = date&.strftime(PREVIEW_DATE)

  # The headline. The bold half is the rule itself; a repeating rule's due date trails it unbolded,
  # because "every 2 months" is the rule and "next due Oct 3" is where the cycle stands today.
  def rule_preview_sentence(preview)
    lead = "#{rule_name(preview.rule)} gets #{number_to_currency(preview.amount)} " \
           "#{rule_preview_schedule_words(preview)}"

    safe_join([tag.strong(lead), rule_preview_due_clause(preview), "."])
  end

  def rule_preview_schedule_words(preview)
    return "every period and keeps what it doesn't spend" if preview.fund?
    return "every period" if preview.rate?
    return interval_label(preview.rule.interval_months) if preview.repeating?

    "by #{rule_preview_date(preview.next_due_on)}"
  end

  def rule_preview_due_clause(preview)
    preview.repeating? ? ", next due #{rule_preview_date(preview.next_due_on)}" : ""
  end

  # What becomes of the money. The dateless arm is for a user who has declared no period, whose
  # rate rule genuinely has no boundary to name.
  def rule_preview_holding_sentence(preview)
    return "It builds up with no limit." if preview.fund?
    return "Each period sets aside its share so the money is there on the day." unless preview.rate?
    return "Whatever's unspent resets when your next period starts." if preview.line.resets_on.blank?

    "Whatever's unspent resets on #{rule_preview_date(preview.line.resets_on)}."
  end

  # Where this rule sits in the give-way order, which is what the type is for.
  TYPE_GIVE_WAY = {
    "bill" => "It's a bill, so it's the last thing to give way.",
    "usage" => "It's usage, so it gives way after your choices and before your bills.",
    "choice" => "It's a choice, so it's the first thing to give way."
  }.freeze

  def rule_preview_type_sentence(preview) = TYPE_GIVE_WAY.fetch(preview.rule.rule_type)
end
