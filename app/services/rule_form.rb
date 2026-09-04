# frozen_string_literal: true

# ** THE ONE TYPED DOOR ONTO A RULE'S COLUMNS (rules-own-the-budget spec §4). **
#
# A rule is seven columns — `amount`, `basis`, `interval_months`, `anchor_date`, `carries_over`,
# `target_amount`, `rule_type` — and only three of them are things a person can be asked about
# directly. The other four are a CODE for two questions: how often does this come round, and what
# becomes of the money nobody spent. §2.1's table is the whole family of legal combinations, and
# every one of the seven rows is reachable from two radios and three inputs — but only if something
# turns the words back into the columns.
#
# ** WHY THE WIRE CARRIES WORDS AND NOT COLUMNS. ** Before this class the form submitted `basis`,
# `interval_months` and `anchor_date` raw, which means every caller that wanted to write a rule had
# to know that `monthly + interval 1 + no anchor` is "every month" while `monthly + interval 1 +
# an anchor` is "every month, due on the 21st", and that `per_period + an anchor` is a shape the
# model refuses outright. That knowledge was spread over the form, the controller and
# `SuggestionEngine`, each spelling a piece of it, and the form could only reach two of §2.1's
# seven rows. It is spelled ONCE here, in both directions:
#
#   `#budget`         the user's words → the columns
#   `.from(budget)`   the columns → the user's words (the edit form, and a proposal's prefill)
#
# ** WHAT THIS CLASS DOES NOT DO IS OWNERSHIP. ** `category_id` and `item_id` arrive off the wire
# and a stranger's id must 404 rather than 422 — a foreign record the user cannot see is not a form
# error, it is a record that does not exist for them — so `BudgetsController#scoped_owners` looks
# both up through `current_user` before this class ever sees them. What the USER is held for here is
# the two collections the form renders (`#category_options`, `#item_options`); the boundary stays
# where §7a drew it.
#
# ** THE TWO KINDS OF LEFTOVER INPUT ARE TREATED DIFFERENTLY, AND DELIBERATELY. **
#
# `unspent` AND ITS TARGET ARE IGNORED where the schedule has no unspent money to speak of, and the
# target is cleared under `resets`. Both are one control — the radio and the field it reveals — and
# the radio's own answer is the whole of what they mean: a user who says "resets" has said there is
# nothing to build toward, and a dated rule's build-up is defined by its DATE
# (`Budget#build_up_must_be_valid` refuses the pair outright). There is exactly one reading of the
# leftover figure, so it is applied rather than argued with.
#
# `anchor_date` AND `interval_months` ARE REFUSED under "How often" instead. There is no such
# reading of a due date on a per-period rule: dropping it changes WHEN the money is needed, which is
# the one thing a bill is about, and the rule that saved would silently not be the rule the user
# described. `RuleForm` refuses it rather than laundering it, and the message lands under the radio
# that decided against it. The Stimulus controller clears a field as it hides it, so with JavaScript
# the refusal is unreachable; without JavaScript every control is on screen and the message lands
# under one the user can see.
class RuleForm
  include ActiveModel::Model

  # THE WORDS ON THE WIRE. `every_n` and `once` are the two dated shapes and they differ only by
  # whether the date repeats; `per_period` and `monthly` are the two dateless ones and they differ
  # only in what a period is.
  SCHEDULES = ["per_period", "monthly", "every_n", "once"].freeze

  # The dateless schedules — the two that may build up, and therefore the only two the "Unspent
  # money" control is asked about at all.
  DATELESS_SCHEDULES = ["per_period", "monthly"].freeze

  UNSPENT_CHOICES = ["resets", "builds"].freeze

  # ** A HAND-MADE RULE IS A PER-PERIOD RATE THAT RESETS (Henry's ruling of 2026-08-20, §2.1 row 1).
  # ** `basis` defaults to `monthly` on the column, which with no interval and no anchor is the one
  # combination `Budget#shape_must_be_valid` refuses outright, so the default has to be stated
  # somewhere. It is stated here, once, and a proposal's own `schedule` simply overwrites it.
  #
  # THE TYPE HAS NO DEFAULT, AND THAT IS NOT AN OVERSIGHT. `budgets.rule_type` defaults to `usage`
  # so an untyped ROW claims neither "must be paid" nor "up to you", but §4 makes the radio REQUIRED:
  # the type decides the give-way order when free money goes below zero, and a form that
  # pre-answered it would be deciding what this person is willing to sacrifice on their behalf. A
  # blank arrives as nil and `Budget`'s presence validation says so, under the radio.
  DEFAULT_SCHEDULE = "per_period"
  DEFAULT_UNSPENT = "resets"

  # EVERY FIELD THE FORM SUBMITS, and `BudgetsController::BUDGET_FIELDS` is this list. Named here
  # because the list IS this class's interface: a field added to the controller and not to this
  # class is a control that writes nothing.
  FIELDS = [
    :category_id,
    :item_id,
    :rule_type,
    :amount,
    :schedule,
    :interval_months,
    :anchor_date,
    :unspent,
    :target_amount
  ].freeze

  # WHERE A `Budget` ERROR LANDS ON THIS FORM — the field whose CHOICE produced the column that was
  # refused. `basis`, `interval_months` and `anchor_date` are all consequences of "How often", so a
  # message about any of them belongs under that radio. The alternative is a 422 whose only visible
  # text is "please review the problems below", which is what an error on an attribute the form does
  # not render produces.
  #
  # ** `target_amount` KEEPS ITS OWN KEY (fix round 1 — L4). ** It is a CONTROL on this form, so
  # "must be greater than 0" belongs under the input the figure was typed into; routed to `:unspent`
  # it printed "Unspent money must be greater than 0" above a pair of radios that were perfectly
  # well chosen. `carries_over` is the one that has no input — it IS the radio — so it alone is
  # worded there.
  BUDGET_ERROR_FIELDS = {
    basis: :schedule,
    interval_months: :schedule,
    anchor_date: :schedule,
    carries_over: :unspent,
    target_amount: :target_amount,
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
                :interval_months,
                :unspent,
                :target_amount

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
  # row of §2.1 or the edit form silently re-shapes a rule the moment it is opened.
  #
  # `every_n` COVERS AN INTERVAL OF ONE. A monthly bill with a due date is `monthly + interval 1 +
  # anchor`, which reads as "every 1 month, first due the 21st" — the same control the six-monthly
  # bill uses, with the same two fields filled in. `Budget#cadence` calls that shape `:monthly` and
  # is right to, because it is answering what a period of this rule IS; this is answering which
  # control the user set, and the two questions part company on exactly this row.
  def self.from(budget)
    schedule = schedule_for(budget)

    {
      category_id: budget.category_id,
      item_id: budget.item_id,
      rule_type: budget.rule_type,
      amount: budget.amount,
      schedule: schedule,
      # NOT the column: `monthly` DERIVES its interval of 1, so handing the 1 back would be a value
      # the user never typed into a control that is not on screen — and #schedule_takes_interval?
      # refuses exactly that on the way in.
      interval_months: (budget.interval_months if schedule == "every_n"),
      anchor_date: budget.anchor_date,
      unspent: budget.carries_over? ? "builds" : "resets",
      target_amount: budget.target_amount
    }
  end

  def self.schedule_for(budget)
    return budget.interval_months.present? ? "every_n" : "once" if budget.anchor_date.present?

    budget.basis_per_period? ? "per_period" : "monthly"
  end

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
    @unspent = choice(@unspent, DEFAULT_UNSPENT)
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
      **schedule_columns,
      **build_up_columns
    )
    budget.rule_type = rule_type if rule_type_known?
  end

  # `per_period` → its own basis and nothing else; `monthly` → an interval of 1, which is row 2's
  # pin (`shape_must_be_valid` refuses an anchorless monthly rule with any other N); the two dated
  # shapes → the basis the anchor needs, with the interval telling them apart.
  def schedule_columns
    case schedule
    when "monthly" then { basis: :monthly, interval_months: 1, anchor_date: nil }
    when "every_n" then { basis: :monthly, interval_months: interval_months.presence, anchor_date: anchor_date }
    when "once" then { basis: :monthly, interval_months: nil, anchor_date: anchor_date }
    else { basis: :per_period, interval_months: nil, anchor_date: nil }
    end
  end

  # A DATED RULE NEVER CARRIES OVER — `Budget#build_up_must_be_valid` refuses the pair, because
  # §3.2's catch-up walk already says what becomes of a dated rule's money. So the radio is not
  # consulted at all there rather than refused: it has a default, and a default is not an opinion.
  def build_up_columns
    return { carries_over: false, target_amount: nil } unless schedule_takes_unspent?
    return { carries_over: false, target_amount: nil } unless unspent == "builds"

    { carries_over: true, target_amount: target_amount.presence }
  end

  def rule_type_known? = rule_type.blank? || Budget.rule_types.key?(rule_type)

  def schedule_takes_unspent? = DATELESS_SCHEDULES.include?(schedule)
  def schedule_takes_interval? = schedule == "every_n"
  def schedule_takes_anchor? = ["every_n", "once"].include?(schedule)

  # ** WHAT THIS FORM ANSWERS THAT `Budget` CANNOT. ** The model validates the COLUMNS, and by the
  # time it sees them the words are gone: `every_n` with no N and a date is indistinguishable from
  # `once` (`shape_must_be_valid` returns early on any anchored rule), and a per-period rule whose
  # date was quietly dropped is a valid rule that is not the one the user described. So the
  # coherence of the CHOICES is asked here, and every message lands on the control that made them.
  def choices_are_coherent?
    errors.clear
    check_known_choices
    check_schedule_fields
    errors.empty?
  end

  def check_known_choices
    errors.add(:schedule, "is not one of the choices on this form") unless SCHEDULES.include?(schedule)
    errors.add(:unspent, "is not one of the choices on this form") unless UNSPENT_CHOICES.include?(unspent)
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
      errors.add(:schedule, "does not take a number of months — choose \"every N months\" to set one")
    end
  end

  def check_anchor
    if schedule_takes_anchor?
      errors.add(:schedule, "needs the date it is first due") if anchor_date.blank?
    elsif anchor_date.present?
      errors.add(:schedule, "does not take a due date — choose \"once\" or \"every N months\" for a dated rule")
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
