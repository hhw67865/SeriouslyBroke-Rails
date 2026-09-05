# frozen_string_literal: true

# ** THE ONE TYPED DOOR ONTO A RULE'S COLUMNS (two-shapes spec §5; rules-own-the-budget §4). **
#
# A rule is five columns — `amount`, `basis`, `interval_months`, `anchor_date`, `rule_type` — and
# only two of them are things a person can be asked about directly. The other three are a CODE for
# one question: WHEN is this money needed. §2's table is the whole family of legal combinations, and
# every row a person can write is reachable from two radios, a checkbox and three inputs — but only
# if something turns the words back into the columns.
#
# ** WHY THE WIRE CARRIES WORDS AND NOT COLUMNS. ** Before this class the form submitted `basis`,
# `interval_months` and `anchor_date` raw, which means every caller that wanted to write a rule had
# to know that `monthly + interval 1 + no anchor` is "every month" while `monthly + interval 1 +
# an anchor` is "every month, due on the 21st", and that `per_period + an anchor` is a shape the
# model refuses outright. That knowledge was spread over the form, the controller and
# `SuggestionEngine`, each spelling a piece of it. It is spelled ONCE here, in both directions:
#
#   `#budget`         the user's words → the columns
#   `.from(budget)`   the columns → the user's words (the edit form, and a proposal's prefill)
#
# ** THE WORDS CHANGED WITH THE SHAPES (two-shapes §5, Henry's ruling of 2026-09-05). ** There were
# four schedules and an "unspent money: resets / builds up" radio revealing a Target field. There are
# TWO schedules and a checkbox:
#
#   per_period            "a spending allowance that resets with your paycheck"
#   by_date               "money saved up toward a day — a bill or a goal", revealing Due <date>
#   by_date + repeats     …and "repeats every [N] months"
#
# `unspent` and `target-amount` are gone with the columns they wrote (§7). A fund IS a dated rule
# whose amount is its target, so "builds up toward $5,000" is written as "$5,000 by Jun 1, 2027" —
# the same words a bill uses, which is why one option covers both.
#
# ** `monthly` LEFT THE FORM AND NOT THE MODEL. ** "$260 every month" with no due date is still a
# legal row (§2 row 2) and `SuggestionEngine` still writes one; the form simply does not OFFER it,
# because it is not a shape people write by hand — and `.from` reads such a row back as `per_period`
# so an existing one opens, edits and saves without silently re-shaping. See `.schedule_for`.
#
# ** WHAT THIS CLASS DOES NOT DO IS OWNERSHIP. ** `category_id` and `item_id` arrive off the wire
# and a stranger's id must 404 rather than 422 — a foreign record the user cannot see is not a form
# error, it is a record that does not exist for them — so `BudgetsController#scoped_owners` looks
# both up through `current_user` before this class ever sees them. What the USER is held for here is
# the two collections the form renders (`#category_options`, `#item_options`); the boundary stays
# where §7a drew it.
#
# ** `anchor_date` AND `interval_months` ARE REFUSED RATHER THAN LAUNDERED, and the refusal lands
# under "When is it needed?". ** There is no honest reading of a due date on a per-period rule:
# dropping it changes WHEN the money is needed, which is the one thing a bill is about, and the rule
# that saved would silently not be the rule the user described. The Stimulus controller clears a
# field as it hides it, so with JavaScript the refusal is unreachable; without JavaScript every
# control is on screen and the message lands under one the user can see.
class RuleForm
  include ActiveModel::Model

  # THE WORDS ON THE WIRE. Two, and `repeats` is what tells the two dated rows apart — a checkbox
  # rather than a third schedule, because "every 6 months" is a detail OF "by a date" and not a
  # different answer to when the money is needed.
  SCHEDULES = ["per_period", "by_date"].freeze

  # ** A HAND-MADE RULE IS A PER-PERIOD RATE (Henry's ruling of 2026-08-20, §2 row 1). ** `basis`
  # defaults to `monthly` on the column, which with no interval and no anchor is the one combination
  # `Budget#shape_must_be_valid` refuses outright, so the default has to be stated somewhere. It is
  # stated here, once, and a proposal's own `schedule` simply overwrites it.
  #
  # THE TYPE HAS NO DEFAULT, AND THAT IS NOT AN OVERSIGHT. `budgets.rule_type` defaults to `usage`
  # so an untyped ROW claims neither "must be paid" nor "up to you", but §5 makes the radio REQUIRED:
  # the type decides the give-way order when free money goes below zero, and a form that
  # pre-answered it would be deciding what this person is willing to sacrifice on their behalf. A
  # blank arrives as nil and `Budget`'s presence validation says so, under the radio.
  DEFAULT_SCHEDULE = "per_period"

  # EVERY FIELD THE FORM SUBMITS, and `BudgetsController::BUDGET_FIELDS` is this list. Named here
  # because the list IS this class's interface: a field added to the controller and not to this
  # class is a control that writes nothing.
  FIELDS = [
    :category_id,
    :item_id,
    :rule_type,
    :amount,
    :schedule,
    :repeats,
    :interval_months,
    :anchor_date
  ].freeze

  # WHERE A `Budget` ERROR LANDS ON THIS FORM — the field whose CHOICE produced the column that was
  # refused. `basis`, `interval_months` and `anchor_date` are all consequences of "How often", so a
  # message about any of them belongs under that radio. The alternative is a 422 whose only visible
  # text is "please review the problems below", which is what an error on an attribute the form does
  # not render produces.
  #
  # ** `carries-over` AND `target-amount` LEFT THE MAP WITH THE COLUMNS (§7). ** They routed to the
  # "Unspent money" radio and to the Target input, neither of which is on this form any more.
  BUDGET_ERROR_FIELDS = {
    basis: :schedule,
    interval_months: :schedule,
    anchor_date: :schedule,
    amount: :amount,
    rule_type: :rule_type,
    item: :item_id,
    category: :category_id
  }.freeze

  attr_reader :user, :budget, :anchor_date
  attr_accessor :category_id,
                :item_id,
                :rule_type,
                :amount,
                :schedule,
                :repeats,
                :interval_months

  # `budget:` IS THE EDIT PATH AND NOTHING ELSE. A new rule is a `Budget.new` this class builds; an
  # existing one is handed in so the words are applied to the row the user is editing — including a
  # SHAPE CHANGE, which §4 rules is legal (the claim is computed, so the walk re-runs from the
  # rule's accrual start under the new shape).
  def initialize(user, params = {}, budget: nil)
    @user = user
    @budget = budget || Budget.new
    assign(params)
    apply_to_budget
  end

  # ** THE COLUMNS → THE WORDS. ** The reverse of `#apply_to_budget`, and it must round-trip every
  # row of §2 or the edit form silently re-shapes a rule the moment it is opened.
  #
  # `repeats` COVERS AN INTERVAL OF ONE. A monthly bill with a due date is `monthly + interval 1 +
  # anchor`, which reads as "by a date, repeating every 1 month" — the same pair of controls the
  # six-monthly bill uses. `Budget#cadence` calls that shape `:monthly` and is right to, because it
  # is answering what a period of this rule IS; this is answering which control the user set, and the
  # two questions part company on exactly this row.
  def self.from(budget)
    schedule = schedule_for(budget)
    repeats = schedule == "by_date" && budget.interval_months.present?

    {
      category_id: budget.category_id,
      item_id: budget.item_id,
      rule_type: budget.rule_type,
      amount: budget.amount,
      schedule: schedule,
      repeats: repeats,
      # NOT the column unless the checkbox is on: an interval handed back for a control that is not
      # revealed is a value the user never typed, and #check_interval refuses exactly that on the way
      # in.
      interval_months: (budget.interval_months if repeats),
      anchor_date: budget.anchor_date
    }
  end

  # ** AN ANCHORLESS `monthly` ROW READS BACK AS `per_period`, AND THE SHAPE SURVIVES THE READ (§5's
  # ruling). ** "$260 every month" with no due date is a legal row and `SuggestionEngine` still
  # writes one, but the form's two options do not include it: this returns `per_period`, whose
  # columns are `basis: per_period, interval nil, anchor nil` — so opening such a rule and saving it
  # unchanged CONVERTS it to a per-period rate stated in the same figure. That is the ruling taken
  # rather than a defect hidden: the shape stays reachable for existing rows and for the suggestion
  # engine, it is not offered, and the form's second option covers what people actually write. The
  # amount is shown per month exactly as it is stored, which is what `budget_page_helper`'s hint
  # says beside it.
  def self.schedule_for(budget) = budget.anchor_date.present? ? "by_date" : "per_period"

  # True and the rule is written, false and `#errors` says why, keyed by the controls on screen.
  #
  # `BudgetProposal` ON THE CREATE PATH, because writing a rule on a category is also what makes
  # that category START HOLDING MONEY (two-ledger spec §4) and the two writes are one act. An
  # UPDATE is a plain save: the category is already holding, and re-stamping `funded_since` would
  # move the date every time somebody corrected an amount.
  def save
    return false unless choices_are_coherent?

    written = budget.new_record? ? BudgetProposal.new(budget: budget).save : budget.save
    carry_budget_errors unless written

    written
  end

  # The category select on the "new" path: this user's EXPENSE categories, because income lands in
  # available and is allocated out of it (two-ledger spec §2), so a rule on one would claim money
  # that category never holds.
  def category_options = user.categories.expenses.order(:name)

  # EVERY ITEM THE USER COULD POINT A RULE AT, all categories at once and each carrying its own
  # `data-category-id`. The select is filtered in the browser rather than re-fetched, so choosing a
  # category re-populates "Pays" with no round trip — and WITHOUT JavaScript the whole list renders
  # and the server still answers, because `Budget#item_must_belong_to_category` refuses an item from
  # somewhere else.
  #
  # ONE STATEMENT, WHATEVER THE SIZE OF THE ACCOUNT. `User#items` is `has_many through: :categories`,
  # so `categories` is ALREADY in the join and `merge(Category.expenses)` and the `categories.name`
  # ordering both reach it — the explicit `.joins(:category)` this used to carry was a second join on
  # the same table (fix round 1 — L5). Pinned by strict statement equality in
  # `spec/requests/budgets_spec.rb`, because a select that grew a query per category would look
  # exactly the same on the page.
  def item_options
    user.items.merge(Category.expenses).order("categories.name", :name)
  end

  delegate :persisted?, to: :budget

  # ** A CHECKBOX, WHICH REACHES A FORM OBJECT AS `"1"` / `"0"` / ABSENT AND NEVER AS A BOOLEAN. **
  # `ActiveModel::Type::Boolean` is the same cast a `boolean` column applies, so the string an
  # unchecked box submits (`"0"`) is false here exactly as it would be in the database — a truthiness
  # test would read it as checked and write an interval onto a one-off.
  def repeats? = ActiveModel::Type::Boolean.new.cast(repeats).present?

  # A DATE, NOT THE STRING THE WIRE CARRIED. `date_field` formats its value with `strftime`, so a
  # String reaches it as a NoMethodError rather than as a rendered form — and this is the one field
  # whose raw value is not already renderable. Everything else is left exactly as it arrived, so a
  # user who typed `40.00` gets `40.00` back on a refusal rather than `40.0`.
  def anchor_date=(value)
    @anchor_date = Budget.type_for_attribute(:anchor_date).cast(value)
  end

  private

  # `params.key?`, not `params[field].present?`: a field the request did not mention is left as it
  # is (the edit path hands in the rule's own words first), while a field it mentioned as BLANK is a
  # cleared control and must reach the columns as one.
  def assign(params)
    params = params.to_h.symbolize_keys
    FIELDS.each { |field| public_send(:"#{field}=", params[field]) if params.key?(field) }

    @schedule = choice(@schedule, DEFAULT_SCHEDULE)
    # NO FALLBACK FOR THE TYPE — see `DEFAULT_SCHEDULE`'s note: the radio is required.
    @rule_type = choice(@rule_type, nil)
  end

  def choice(value, fallback) = value.presence&.to_s || fallback

  # ** THE WORDS → THE COLUMNS (§2.1's table, in one method). ** Run in the constructor rather than
  # in `#save`, so `#budget` is the record these words describe on every path — the form re-renders
  # from it after a refusal, and `BudgetsController#edit` reads its amount for the "currently…"
  # line.
  def apply_to_budget
    budget.assign_attributes(
      category_id: category_id.presence,
      item_id: item_id.presence,
      amount: amount,
      **schedule_columns
    )
    budget.rule_type = rule_type if rule_type_known?
  end

  # ** §2'S TABLE, IN THREE ROWS. ** `per_period` → its own basis and neither of the other two
  # columns; `by_date` → the `monthly` basis an anchor needs, with `repeats` deciding whether an
  # interval rides along. The one-off is `interval NULL` and is the shape a goal takes.
  def schedule_columns
    return { basis: :per_period, interval_months: nil, anchor_date: nil } unless schedule == "by_date"

    { basis: :monthly, interval_months: (interval_months.presence if repeats?), anchor_date: anchor_date }
  end

  def rule_type_known? = rule_type.blank? || Budget.rule_types.key?(rule_type)

  def schedule_takes_interval? = schedule == "by_date" && repeats?
  def schedule_takes_anchor? = schedule == "by_date"

  # ** WHAT THIS FORM ANSWERS THAT `Budget` CANNOT. ** The model validates the COLUMNS, and by the
  # time it sees them the words are gone: a repeating rule with no N is indistinguishable from a
  # one-off (`shape_must_be_valid` returns early on any anchored rule), and a per-period rule whose
  # date was quietly dropped is a valid rule that is not the one the user described. So the
  # coherence of the CHOICES is asked here, and every message lands on the control that made them —
  # which for both the date and the interval is "When is it needed?", the question they are details
  # of.
  def choices_are_coherent?
    errors.clear
    check_known_choices
    check_schedule_fields
    errors.empty?
  end

  def check_known_choices
    errors.add(:schedule, "is not one of the choices on this form") unless SCHEDULES.include?(schedule)
    errors.add(:rule_type, "is not a kind of rule") unless rule_type_known?
  end

  def check_schedule_fields
    return unless SCHEDULES.include?(schedule)

    check_interval
    check_anchor
  end

  def check_interval
    if schedule_takes_interval?
      errors.add(:schedule, "needs the number of months it comes round in") if interval_months.blank?
    elsif interval_months.present?
      errors.add(:schedule, "does not take a number of months — tick \"repeats\" to set one")
    end
  end

  def check_anchor
    if schedule_takes_anchor?
      errors.add(:schedule, "needs the date it is first due") if anchor_date.blank?
    elsif anchor_date.present?
      errors.add(:schedule, "does not take a due date — choose \"By a date\" for a dated rule")
    end
  end

  # `Budget`'S REFUSALS, RE-KEYED ONTO THE CONTROLS THAT CAUSED THEM. Anything unmapped keeps its
  # own key, and `:base` stays `:base` — an owner-less rule is a fact about the whole record and the
  # form prints base errors in its own notification.
  #
  # THE ONE EXCEPTION IS THE CATCH-ALL RULE, which `Budget` states on `:base` because it is about
  # the record rather than about a column — but on THIS form it is about a control: the sentence's
  # own second half ("or point this rule at a single item") is the "Pays" select, three rows up. It
  # is routed by the message's identity rather than by matching its words, which is why
  # `Budget::CATCH_ALL_TAKEN` is a constant.
  def carry_budget_errors
    budget.errors.each do |error|
      errors.add(form_field_for(error), error.message)
    end
  end

  def form_field_for(error)
    return :item_id if error.attribute == :base && error.message == Budget::CATCH_ALL_TAKEN

    BUDGET_ERROR_FIELDS.fetch(error.attribute, error.attribute)
  end
end
