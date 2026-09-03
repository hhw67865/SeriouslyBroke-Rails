# frozen_string_literal: true

# CHANGING HOW LONG A PERIOD IS, AND WHAT THAT DOES TO THE RULES STATED IN PERIODS
# (computed-claims spec §3.5).
#
# Dated rules are time-proportional — the catch-up formula re-plans on whatever grid exists, so
# "built up so far" stays exactly where it was and nothing needs asking. Rate rules are PER PERIOD
# BY DEFINITION: $400 a period means $10,400 a year on a fortnightly grid and $4,800 on a monthly
# one, so the same number is a different budget the moment the cadence moves. The app cannot know
# which the user meant, so it OFFERS: monthly → biweekly, ×12/26, one confirm, their choice.
#
# ** THE OFFER AND THE CHANGE COMMIT TOGETHER, IN ONE TRANSACTION. ** Writing the cadence first and
# the amounts afterwards leaves a failed second half as a budget stated in the wrong unit — every
# figure on the page halved or doubled, with no message saying so. `#apply` writes both or neither.
#
# ** ONLY `per_period` RATE RULES ARE SCALED, and the exclusion is arithmetic rather than taste. **
# A rule stated in CALENDAR time — "$260 a month" — already means the same thing on every grid, and
# `Budget#steady_ask` is what divides it by `periods_per_year`. Scaling it here would apply the
# ratio twice: $260 a month would be rewritten to $120 and then divided again to $55 a fortnight,
# which is 8 cents in the dollar of what the user said. The shape test is
# `ClaimCalculator#shape` — the app's one classification of what a rate rule IS — narrowed to the
# rules whose amount is denominated in periods.
class CadenceChange
  # ONE RULE'S OFFER: what it says now and what it would say after. The rule travels with the pair
  # so the confirm screen and the write are looking at the same record rather than at a name.
  Line = Data.define(:rule, :amount, :scaled_amount)

  # A RATE MAY NOT BE ZERO (`Budget` validates `amount > 0` for every shape but the dateless
  # set-aside-only target, which is not a rate rule). A one-cent weekly rule scaled to a monthly
  # grid rounds to nothing, and a confirm that wrote an invalid row would 500 on a button the user
  # was right to press. The floor is the smallest amount the column can hold.
  SMALLEST_RATE = BigDecimal("0.01")

  attr_reader :user, :declaration, :periods_per_year_before

  # `periods_per_year` IS CAPTURED AT BIRTH, before anything is written: it is the OLD divisor, and
  # `#apply` updates the user in the middle of its own transaction. Reading it lazily would give
  # the ratio a value that depends on when it was first asked for.
  def initialize(user:, declaration:)
    @user = user
    @declaration = declaration
    @periods_per_year_before = user.periods_per_year
  end

  # IS THERE A QUESTION TO ASK? Three conditions, and each one is a way the offer would otherwise
  # be wrong rather than merely unnecessary:
  #
  #   * the cadence is really MOVING (see #changing?);
  #   * there is something to scale — a user with no per-period rate rule would meet a list of
  #     nothing above two buttons that do the same thing;
  #   * the declaration would actually be ACCEPTED. A cadence with no anchor is refused by `User`,
  #     and asking about amounts first would put a question in front of an error — the user would
  #     answer it, press a button, and only then be told the period could not be saved at all.
  def offered? = changing? && acceptable? && lines.any?

  # ** NEITHER A BLANK CADENCE NOR A FIRST ONE IS A CHANGE. ** Clearing the period back to
  # undeclared leaves every figure provisional (`User#periods_per_year` falls back to 12), and there
  # is no grid the user has named to scale onto. DECLARING one for the first time is the same
  # argument from the other side: the amounts were never denominated in a period the user had
  # stated, so there is no old unit to convert from — scaling by the 12-a-year fallback would be
  # converting from an assumption the app made rather than from anything they said. Both go through
  # as they always did, and the rules keep their numbers.
  def changing? = cadence.present? && user.period_cadence.present? && cadence != user.period_cadence

  def cadence = declaration[:period_cadence].presence

  def periods_per_year = User::PERIODS_PER_YEAR.fetch(cadence, 12)

  def lines
    @lines ||= scalable_rules.map do |rule|
      Line.new(rule: rule, amount: rule.amount.to_d, scaled_amount: scaled(rule.amount.to_d))
    end
  end

  # BOTH HALVES OR NEITHER. `scale` is the user's answer — true scales the rules, false leaves them
  # alone, and either way the cadence itself only lands if `User`'s own validations accept it (a
  # cadence with no anchor is still refused here exactly as it was before this class existed).
  #
  # `raise ActiveRecord::Rollback` RATHER THAN `return`: returning out of a transaction block
  # COMMITS it in Rails 7 and later, which would write the cadence the model had just rejected.
  def apply(scale: nil)
    saved = false

    ActiveRecord::Base.transaction do
      saved = user.update(declaration)
      raise ActiveRecord::Rollback unless saved

      lines.each { |line| line.rule.update!(amount: line.scaled_amount) } if scale
    end

    saved
  end

  private

  # WOULD THE DECLARATION SAVE? Asked of a SECOND instance of the same row, never of `user`:
  # assigning to `user` here would leave the rejected values on the object the confirm screen's
  # presenter then reads, which is exactly the defect `BudgetPagePresenter#declaration` exists to
  # record. The probe is thrown away and nothing is written either way.
  def acceptable?
    probe = User.find(user.id)
    probe.assign_attributes(declaration)
    probe.valid?
  end

  def scaled(amount) = [(amount * periods_per_year_before / periods_per_year).round(2), SMALLEST_RATE].max

  # `ClaimCalculator#shape`, WHICH COSTS NOTHING TO ASK: it reads `rule.anchor_date` and
  # `category.target_amount` and no more, so a probe calculator here runs no query. Spelling the
  # two-column test again would be a second classification free to drift from the one every claim
  # on the page is computed by.
  def scalable_rules
    Budget.for_user(user).includes(:category).select do |rule|
      rule.basis_per_period? && rule.claim_calculator.rate?
    end
  end
end
