# frozen_string_literal: true

class Budget < ApplicationRecord
  # A RULE BELONGS TO THE THING THAT HOLDS THE MONEY (two-ledger spec §3): `budgets.category_id`
  # replaced `budgets.pool_id`, one category to one budget line, and Task 8 dropped the column the
  # pool arm read. `budgets.category_id` is NOT NULL at the database now.
  #
  # `optional: true` SURVIVES THE POOL IT WAS SHARED WITH, AND IT IS NOT AN OVERSIGHT. A required
  # `belongs_to` validates presence by READING the attribute, and `budgets.category_id` is younger
  # than `spec/migrations/two_ledger_spec.rb`, which plants rules through this model against a
  # schema rewound past the column (see `#category_column?`). Reading an attribute the database does
  # not have raises rather than rejecting, so the presence rule is stated by `#must_have_a_category`
  # below, behind the same gate every other reader of the column is behind.
  belongs_to :category, optional: true, touch: true
  belongs_to :item, optional: true

  # THE DATED, SIGNED DELTAS ON THIS RULE'S ACCRUAL (computed-claims spec §3.3). `dependent: :destroy`
  # because an adjustment is a delta on a schedule: with the rule gone there is no accrual for it to
  # be a delta ON, and a `+$500 into Vacation` left behind would be a claim with no arm to land on.
  #
  # `foreign_key: :rule_id` — the column is named for the app's word for a `budgets` row, and this is
  # the one place the two spellings meet (see the migration's header).
  has_many :adjustments, foreign_key: :rule_id, dependent: :destroy, inverse_of: :rule

  enum :basis, { monthly: 0, per_period: 1 }, prefix: true

  # ** WHAT KIND OF RULE THIS IS (rules-own-the-budget spec §3, Henry's ruling of 2026-09-04). **
  # `bill` must be paid (rent, insurance); `usage` is a real need whose amount moves with how you
  # live (power, groceries, fuel); `choice` is discretionary (restaurants, the vacation fund). It is
  # a fact about the RULE and not about the category, because one category can carry a fixed bill on
  # one of its items and a discretionary catch-all beside it.
  #
  # UNPREFIXED, so the predicates read `rule.bill?` — the word the spec, the Budget page's label and
  # the give-way copy all use. `basis` is prefixed because `monthly?` on its own would be a claim
  # about the CADENCE, which `#cadence` answers with a different four-arm classification.
  enum :rule_type, { bill: 0, usage: 1, choice: 2 }

  # ** THE GIVE-WAY ORDER (§3), SPELLED ONCE. ** When free money goes below zero the app names the
  # claims that are not covered, and it names them in the order a person would actually sacrifice
  # them: the restaurant budget before the power bill, the power bill before the rent. That is the
  # REVERSE of how urgent each type is, which is why it cannot be the enum's own order — the enum's
  # integers are storage and were chosen to read bill-first, and re-numbering them to make `sort_by`
  # work would rewrite every row in the table to express an opinion about presentation.
  #
  # ** WITHIN A TYPE, THE HIGHEST PRIORITY NUMBER GIVES WAY FIRST, and the direction is worth
  # spelling out because it is the OPPOSITE of the list it is read from. ** `Category.in_fill_order`
  # is `[priority, name]` ASCENDING — lowest first — and that ordering is the fill order: who would
  # have been funded soonest. The give-way order is that list read BACKWARDS, because the category
  # that would have been funded LAST is the one that goes without first. `HomePresenter
  # #give_way_rank` is the one place it is spelled (the negated index into `#budgeted_categories`),
  # so the drag reorder survives untouched and there is no second copy of the key here to drift.
  # A tie on priority breaks on the LATER name, for the same reason.
  #
  # WITHIN A CATEGORY, the existing `Category.rule_order`. Type decides before priority does, which
  # is what closes the intra-category ordering question §3 opens.
  TYPE_RANK = { choice: 0, usage: 1, bill: 2 }.freeze

  # `fetch`, not `[]`: a fourth type added to the enum without a rank is a sorting bug that would
  # otherwise surface as every new rule silently ranking `nil` and blowing up in the comparator.
  def type_rank = TYPE_RANK.fetch(rule_type.to_sym)

  # ** ONE CATEGORY, ONE CATCH-ALL RULE — the sentence, hoisted to a constant so it has an IDENTITY
  # and not just a spelling (rules-own-the-budget §4). ** `#category_may_hold_one_item_less_rule`
  # states it on `:base`, because it is a fact about the whole record; `RuleForm` has to move it
  # onto the "Pays" control, because on that form it is a fact about a control — the sentence's own
  # second half ("or point this rule at a single item") IS that select. Routing it by comparing the
  # message text would be a copy of the sentence living in a second file, one rewording away from
  # silently landing back in the form's banner.
  CATCH_ALL_TAKEN = "this category already has a rule covering all of its spending — change that " \
                    "one instead, or point this rule at a single item"

  # EVERY RULE A USER OWNS, IN ONE RELATION — the reader `User has_many :budgets, through:
  # :categories` cannot be. That association walks the category link only, which after the cutover
  # reaches NOTHING at all, and every rule the Budget page manages is invisible to it.
  # `current_user.budgets.find` therefore answered RecordNotFound for rules the user plainly owns.
  #
  # THE CAP'S CATEGORY ARM WENT IN PLAN 3, AND THIS IS NOT IT COMING BACK. The scope was
  # `where(category_id: user.categories).or(where(pool_id: user.pools))` because a rule could be a
  # per-category CEILING on a pool-funded envelope; that shape is gone and its pins were withdrawn
  # with it. The arm that is left means the opposite thing — the category is the OWNER now, the
  # thing that holds the money — and it is reached by the same SQL only because the same column
  # happens to say who owns what.
  #
  # ONE LANE SINCE TASK 8, which dropped `budgets.pool_id`. The OR existed so a rule written through
  # the pool form and a rule written on a category were both found while the two lanes coexisted;
  # there is one lane, so the `.or` would now be a branch that can never match.
  #
  # Scoped by the OWNER's user, not by a `user_id` on this table — a budget carries no user
  # column, and inventing one would give the invariant two places to be wrong.
  scope :for_user, ->(user) { where(category_id: user.categories.select(:id)) }

  # ** THE CATEGORIES SAVING TOWARD A DAY (two-shapes spec §2/§7) — THE ONE SPELLING, IN SQL. ** It
  # replaces `BUILDS-UP-THE-CATEGORY` (`item_id: nil, carries-over: true`) and its two derived
  # readers, which asked "does this rule's unspent money survive the boundary" — a question no column
  # answers any more. What the dashboard's Savings band is about is a target with a DAY on it: a
  # one-off dated rule, which is `anchor_date IS NOT NULL AND interval_months IS NULL` and is exactly
  # §2's row 5 (a goal). A rule that REPEATS is a recurring bill, not something being saved toward.
  #
  # ** THE SCOPE AND THE PREDICATE COME OFF ONE PAIR OF HASHES (fix wave — MED-2), which is
  # `BUILDS_UP_THE_CATEGORY`'s own pattern from the plan before this one. ** The comment here used to
  # say "ONE SCOPE AND NO IN-MEMORY TWIN, deliberately" and there were two twins under it:
  # `Dashboard::OverviewPresenter#saving_toward_a_date?` and `CategoryBudgetPresenter#fund_line` each
  # spelled the four clauses out in Ruby, because both are asked of rows something else has already
  # LOADED — the strip's `includes(:budgets)` and the category card's one `ClaimLedger` — and
  # `budgets.merge(scope).first` issues a statement against a loaded association, which is a SELECT
  # per card. So the twin is real and necessary; what was wrong was that it was written out twice
  # more, free to drift from the SQL and from each other. Both readers ask `#saving_toward_a_date?`
  # now, and the equivalence over every clause combination is pinned in `budget_spec`.
  #
  # TWO HASHES BECAUSE TWO OF THE CLAUSES ARE NEGATIVE, and `where.not(a, b)` is `NOT (a AND b)` —
  # which would list an interval-less rule with no anchor as savings. They are chained one at a time
  # for the same reason.
  #
  # `self[column].to_s` IN THE PREDICATE: `rule_type` is an enum and reads back as a STRING, while
  # the scope names it as the symbol the enum declares. Every other column compares as itself, and
  # `nil.to_s` is `""` for exactly the two columns whose required value is nil.
  SAVING_TOWARD_A_DATE = { item_id: nil, interval_months: nil }.freeze
  NOT_SAVING_TOWARD_A_DATE = { anchor_date: nil, rule_type: :bill }.freeze
  #
  # ** `item_id IS NULL` SURVIVES THE CHANGE OF SHAPE UNCHANGED, and it is §3.1's lane partition. **
  # An item-backed rule speaks for ONE item's spending, so a goal carved out for the flights line is
  # not what the CATEGORY is saving toward — the same sentence the retired pair carried, asked of the
  # new columns. It is also what makes the scope SINGLE-VALUED per category
  # (`#category_may_hold_one_item_less_rule` allows exactly one item-less rule), which is what lets
  # the dashboard's row name "the fund" rather than pick one of a set.
  #
  # ** AND A `bill` IS NOT SAVING, WHICH IS THE CLAUSE THE DATE ALONE CANNOT DRAW (fix round 1 —
  # LOW-7). ** A one-off dated rule on the whole category is the shape of a goal AND the shape of a
  # single bill nobody has itemised — the quarterly tax estimate, the annual registration — and the
  # walk cannot tell them apart, because it is the same walk. What tells them apart is the word the
  # user chose: `bill` is "must be paid", which is not money being saved toward a thing. `usage` and
  # `choice` both are, so the band lists them and leaves the household's tax estimate off a strip
  # headed "Savings".
  scope :saving_toward_a_date,
        lambda {
          NOT_SAVING_TOWARD_A_DATE.reduce(where(SAVING_TOWARD_A_DATE)) do |relation, (column, value)|
            relation.where.not(column => value)
          end
        }

  # A rule that demands nothing is what deleting it is for, and a negative one is money
  # flowing the wrong way.
  #
  # ** ZERO IS LEGAL FOR NO SHAPE AT ALL SINCE THE TWO SHAPES (§2, Henry's ruling of 2026-09-05). **
  # The one exemption was `#set-aside-only` — a dateless target fed only by hand, which spelled "no
  # standing rate" as an amount of zero because there was no deadline for a rate to be derived from.
  # A goal names a DAY now, so its per-period share is `remaining ÷ periods until the date` and its
  # amount is the target itself: there is nothing left for a zero to mean. `TwoShapes` converts every
  # such rule to `amount = target-amount`, so no row in any database this app can meet still holds
  # one.
  validates :amount, presence: true
  validates :amount, numericality: { greater_than: 0 }
  validates :interval_months, numericality: { greater_than: 0 }, allow_nil: true

  # EVERY RULE HAS A TYPE (§3). The column is NOT NULL with a default, so this fires only on a rule
  # somebody explicitly blanked — which is exactly the state a form with an unanswered radio would
  # submit, and the message belongs under that radio rather than as a 500 from the database.
  validates :rule_type, presence: true

  validate :must_have_a_category
  # ** A DATED RULE NEVER KEEPS (two-shapes spec §12). ** Behind `#keeps_column?` on
  # `#must_have_a_category`'s own reasoning: `spec/migrations/a_fund_keeps_unspent_spec.rb` rewinds
  # the schema past the column for the length of the file, and a validator that READS a missing
  # attribute raises instead of rejecting.
  validate :keeps_unspent_never_dates, if: :keeps_column?
  validate :category_must_be_an_expense, if: :category_mode?
  validate :item_must_belong_to_category, if: :category_mode?
  validate :category_may_hold_one_item_less_rule, if: :category_mode?
  # UNGATED, BOTH OF THEM: `#shape_must_be_valid` is about the three columns that spell a cadence
  # and `#item_must_not_be_claimed` is about one item having one rule, so neither has ever needed
  # to know who owns the rule.
  validate :shape_must_be_valid
  validate :item_must_not_be_claimed

  # `#category_column?` FIRST, AND IT IS NOT DEFENSIVE. `budgets.category_id` is younger than
  # `spec/migrations/two_ledger_spec.rb`, which rewinds the schema past `CategoriesHoldTheMoney` —
  # whose whole subject is ADDING this column — for the length of the file. Reading an attribute the
  # database does not currently have raises NameError, and a predicate that raises is not an answer.
  # Asked once here and once in #user, which are the only two readers of the column outside a
  # validator gated on this method.
  #
  # `spec/seeds_spec.rb` USED TO BE THE SECOND SPEC ON THIS LIST and no longer rewinds anything
  # (Task 8): the seeds are category-native and cannot be replanted against a schema that has no
  # `funded_since` and no `allocations`.
  def category_mode? = category_column? && (category_id.present? || category.present?)

  # nil-safe: an owner-less budget is exactly the state the form re-renders in
  # after a failed submission, and a rewound schema has no `category_id` for a rule to carry.
  def user = category_mode? ? category&.user : nil

  # THE OWNER'S TODAY (fix round 2 — LOW-1), through the category that knows who the owner is.
  # `User#today` carries why this is not `Date.current`; `Category#today` carries the owner-less
  # fallback. What is left here is the CATEGORY-less arm, which is the same state `#user` above is
  # nil-safe for — a rule re-rendered from a failed form, which no calculator is built from.
  #
  # It is the default for the `today:` this class hands down, so two readers on one row cannot be
  # asked about two different days by the same caller.
  def today = category&.today || Date.current

  # WHAT THIS RULE CLAIMS FROM THE USER'S MONEY (computed-claims spec §3) — the ONE door onto the
  # claim, and the port of `Category#holding_calculator`'s role: `spending:` and `adjustments:` thread
  # straight through and DEFAULT TO NOTHING, which keeps this the unbatched single-rule door. Only the
  # callers that ITERATE rules build a `ClaimLedger` and let it inject the grouped rows.
  #
  # A SECOND CONSTRUCTION PATH IS HOW A KEYWORD ENDS UP HONOURED ON ONE SCREEN AND FORGOTTEN ON THE
  # NEXT, so nothing outside `ClaimLedger` calls `ClaimCalculator.new` itself.
  #
  # IT WAS NOT THE ONLY CALCULATOR ON THIS ROW UNTIL THE FIX WAVE. `#calculator` built a
  # `BudgetCalculator` — what the rule needed from the next DISTRIBUTION — and Task 4 was meant to
  # delete it along with the distribution. It survived on one branch of `#steady_ask` with a due date
  # the claims overrule; both are gone now (see `#one_off_steady_ask`), and that branch reads
  # `ClaimCalculator#standing_ask`, which touches neither `spending:` nor `adjustments:` and so costs
  # this door no query when it is built unbatched.
  def claim_calculator(today: self.today, spending: nil, adjustments: nil)
    ClaimCalculator.new(self, today: today, spending: spending, adjustments: adjustments)
  end

  # ** WHICH OF §3'S TWO FORMULAS THIS RULE TAKES — `ClaimCalculator#shape`, AND THE ONLY DOOR ONTO
  # IT FROM OUTSIDE A CALCULATOR (fix wave — MED-2). ** The shape is read off `anchor_date` alone
  # since the two shapes (§2); it was that column plus `carries-over` before, and the CATEGORY's
  # `target-amount` before that — and `SuggestionEngine#rate_shape?` held a second reading of it that
  # asked neither: `anchor_date.blank? && item_id.blank? && cadence.in?([:per_period, :monthly])`. It
  # is missing the target column, so every goal category's rule was a "rate rule" to the drift
  # detector — including the eight $0 rules Task 4's migration minted, which fired "your rule says
  # $0.00, you spend $X" at a fund the user feeds by hand, and a $50-a-period goal with heavy
  # spending, which was told to RAISE its contribution. One spelling, on the class that owns §3.
  #
  # IT COSTS NO QUERY WHERE THE OWNER IS LOADED: `#shape` reads two columns and the constructor's
  # `today:` default walks `category.user`, which every caller of this method already preloads.
  def claim_shape = claim_calculator.shape

  # ** THE IN-MEMORY SIDE OF `.saving_toward_a_date`, AND IT READS THAT SCOPE'S OWN TWO HASHES
  # RATHER THAN RESTATING THE CLAUSES (fix wave — MED-2). ** See the note beside the constants for
  # why the twin exists at all (both callers ask it of rows already loaded, where the relation would
  # cost a statement per card) and why the negative half is a second hash.
  #
  # `self[column]` and not the attribute readers, so the columns are named in exactly one place;
  # `.to_s` because `rule_type` is an enum, which reads back as a string against the scope's symbol.
  def saving_toward_a_date?
    SAVING_TOWARD_A_DATE.all? { |column, value| self[column].to_s == value.to_s } &&
      NOT_SAVING_TOWARD_A_DATE.none? { |column, value| self[column].to_s == value.to_s }
  end

  # HOW OFTEN THIS RULE COMES ROUND, as one symbol. `basis`, `interval_months` and `anchor_date`
  # are three columns whose COMBINATION is the shape (§3.1), and reading the shape off them takes
  # a four-branch cascade in an order that is a hazard in itself — so the cascade lives once,
  # here, and the two helpers that used to hold a copy each keep only their own words:
  # `HomeHelper#pool_rule_label` names a rule ("Every 6 months") and
  # `BudgetPageHelper#budget_rule_basis` says what an amount is per ("every 6 months").
  # Classification is the model's; wording is each screen's.
  #
  # `:every_n` names the shape without naming the number — the interval is on the record and each
  # caller interpolates its own, so this stays a fixed set of four rather than a symbol per N.
  #
  # `basis_per_period?` FIRST: a per-period rule carries no interval either, so testing the
  # interval first would call every rate rule a one-off.
  #
  # THE CATEGORY-CAP ARM IS GONE. A cap carried no interval at all (#shape_must_be_valid ran in
  # pool mode only), so it needed answering before the nil-interval branch could call it a one-off.
  # There is no cap to answer for now, and every rule reaching here has been through
  # #shape_must_be_valid — so a blank interval really does mean a one-time bill.
  def cadence
    return :per_period if basis_per_period?
    return :one_off if interval_months.blank?
    return :monthly if interval_months == 1

    :every_n
  end

  # PER-PERIOD STEADY-STATE COST OF THIS RULE — what it claims from a typical period, NOT what
  # it asks this period. That second question is `ClaimCalculator#planned_this_period`, and the two
  # are deliberately different figures with deliberately different names:
  #
  #   #planned_this_period — this period's ask. Catch-up on a bill that slipped, zero on one
  #                 already funded, the whole remainder on one whose date has gone by. It moves
  #                 with the fund, with the spending and with the calendar, and it is what a rule's
  #                 ROW and the adjust panel print.
  #   #steady_ask — the standing claim. What this rule costs a period FOREVER, assuming nothing
  #                 is behind and nothing is ahead. It moves only when the rule itself changes
  #                 (or the grid under it does).
  #
  # §9's structural check ("your rules need $X a period / you typically bring in $Y") is a
  # question about the SHAPE of a budget, so it can only be asked of the steady figure. Asked of
  # this period's figure it answers a different question in the same words — measured, and it is why
  # this method exists in this shape (fix wave 2 — MED-A): a $600 one-off anchored a month ago and
  # unpaid prices at the whole $600 under catch-up, fires "your budget doesn't fit your income", and
  # CLEARS the verdict the afternoon the bill is paid, with no rule changed.
  #
  # BUILT ON #cadence, not on a fifth reading of `basis`/`interval_months`/`anchor_date`. The
  # shape classification is that method's and the two helpers that used to hold a copy each were
  # collapsed into it one task ago; a private cascade here would reopen exactly that seam.
  #
  # `amount * 12 / (periods_per_year * interval)` rather than `amount / periods_in_interval`, and
  # the difference is not cosmetic: `periods_in_interval` for a monthly rule under a biweekly user
  # is 26/12 = 2.1666…, and an Integer spelling of it truncates to 2 — a monthly rule would ask
  # for half its amount every fortnight, 8% over the year. Dividing once, at the end, keeps the
  # fraction. `amount.to_d` first because an in-memory record assigned `amount: 260` holds an
  # Integer and `Integer * 12 / Integer` truncates the cents.
  #
  # `user` is the divisor's owner. The one-off branch reaches the rule's OWN owner through the
  # calculator instead (`ClaimCalculator#user`); the two are the same record by construction, since
  # every caller reaches this through `Budget.for_user(user)`.
  #
  # `today:` is not in the plan's sketch and is needed: every calculator in this app takes a clock
  # and this method builds one, so a caller with a fixed clock must be able to hand its own down
  # rather than have this reach for a clock behind it. Unhanded, it reads the OWNER's day off the
  # user it is already given (fix round 2 — LOW-1), not the ambient one. THE ONE-OFF FIGURE ITSELF
  # DOES NOT MOVE WITH IT (fix wave 2 — MED-A): `#standing_ask` is a constant of the rule and the
  # grid, and the clock only decides which owner's day a walk would open on.
  #
  # THIS DIVIDES A MONTHLY RULE BY `periods_per_year` WHILE ITS PERIOD STILL ENDS ON THE CALENDAR
  # MONTH, and the divergence is deliberate (plan 2d decision 5). A $260-a-month rule under a
  # biweekly cadence costs $120 a period — always, in every month — because that is what a standing
  # monthly rate means spread over 26 periods. Its LIFECYCLE is a different question: the month is
  # the span the user said the money is for, and `User#period_containing` closes it at month end for
  # an undeclared user for the same reason.
  #
  # Cost and lifecycle are not the same question, so one answer for both would be wrong for one of
  # them. Measured in both directions: costing by the calendar's boundaries made this rule answer
  # $130 in nine months of 2026 and $86.67 in the two holding a third boundary (see above), and
  # ending its period by `periods_per_year` instead would roll a monthly rule mid-month and fund it
  # twice inside one month.
  #
  # ** THERE IS NO `claim:` SEAM ANY MORE (fix wave 2 — MED-A). ** It existed so `.steady_need` could
  # hand the one-off branch a BATCHED calculator, because that branch read `#planned_this_period` and
  # an unbatched calculator runs a spending query and an adjustment query to answer it.
  # `#standing_ask` reads two columns and the period grid and NOTHING ELSE, so the branch costs no
  # statement at all and a seam that saved statements has nothing left to save. A calculator built
  # here is an object, not a query.
  def steady_ask(user, today: user.today)
    case cadence
    when :per_period then amount.to_d
    when :one_off then one_off_steady_ask(today)
    else (amount.to_d * 12 / (user.periods_per_year * (interval_months || 1))).round(2)
    end
  end

  # WHAT THIS USER'S FUNDING RULES CLAIM FROM ONE PERIOD — the single reader behind §9's
  # structural check, `BudgetPagePresenter#rules_need` and `HomePresenter#structurally_underwater?`
  # alike. Two screens asking the same question of two different sums is how one page tells a user
  # their budget fits while the other says it does not.
  #
  # THE EXCLUSION THIS FIGURE WAS BUILT AROUND IS NOW EMPTY, AND THAT IS THE HONEST THING TO SAY.
  # It used to read `for_user(user).where.not(pool_id: nil)`, and the `where.not` was the whole
  # argument: a category-mode cap is a SPENDING LIMIT on tracking, not a funding claim on income —
  # `AllocationCalculator` never read one, so no distribution ever asked for a penny on account of
  # one, and counting one would have inflated "your rules need" by money that will never be asked
  # for. On the pre-cutover demo that was $1,523.08 a period of double-counting, a "Housing" cap of
  # $1,500 a month sitting over the top of the $1,500 Rent rule that actually filled the envelope.
  #
  # Caps do not exist. `#for_user` is category-scoped by construction now, so the mode filter it used
  # to stack on top of it would be a `where.not` that can never exclude a row — a condition kept for
  # the sentence it lets a comment say, which is how dead filters survive. It is gone; the boundary
  # it drew survives as a fact about the data rather than a clause in a query.
  #
  # TASK 9 INHERITS THE SAME SUM: the sacrifice view's cut list is exactly the rules counted here,
  # because the gap it is closing is this figure. It should not re-derive the population.
  #
  # `sum(0.to_d)` with an explicit BigDecimal seed. An empty relation's `sum` is Integer `0`, and
  # this figure is compared against `typical_income` and subtracted from it — the seed keeps a
  # user with no rules at all on the same numeric type as one with them.
  #
  # ** IT ITERATES THE `ClaimLedger`'s RULES WHERE ONE IS OFFERED, AND THE SAVING IS THE RELATION
  # RATHER THAN THE ROWS (fix wave — MED-3, corrected in fix wave 2 — MED-A). ** The `ledger:` seam
  # was introduced to hand each one-off rule a BATCHED calculator, because the branch then read
  # `#planned_this_period` and an unbatched calculator queried spending and adjustments per rule.
  # `#standing_ask` reads no rows at all, so no calculator here costs a statement and the seam's
  # value is now the LOADED RULES: Home and the Budget page have already paid for
  # `for_user(user).includes(:item, category: :user)` and this sum reuses it instead of running the
  # same relation and the same two preloads a second time. Handed nothing it builds a ledger and asks
  # it only for `#rules` — the grouped spending and adjustment statements are lazy, so a caller that
  # wants only this figure never pays for them.
  #
  # THE PRELOAD IS WHAT THE COST PIN IS ABOUT. A budget has no user column, so `#user` walks the
  # category, and without the nested preload that is two un-preloaded queries per rule that reaches
  # for a clock — which every one-off rule does.
  #
  # PINNED, not asserted: `budget_steady_ask_spec`'s "costs the same number of queries for five
  # dated rules as for one" counts the statements, because a preload that quietly stops covering a
  # lane is invisible to every other example in that file.
  def self.steady_need(user, today: user.today, ledger: nil)
    rules = (ledger || ClaimLedger.new(user, today: today)).rules

    rules.sum(0.to_d) { |budget| budget.steady_ask(user, today: today) }
  end

  private

  # ** A ONE-TIME RULE HAS NO INTERVAL TO DIVIDE BY, SO THE CALENDAR IS THE DIVISOR: its amount over
  # the periods between the day it started accruing and the day it falls due.
  # `ClaimCalculator#standing_ask` IS that figure and this branch reads nothing else (fix wave 2 —
  # MED-A). **
  #
  # ** IT WAS `#planned_this_period` FOR ONE WAVE, AND THAT MADE A STANDING FIGURE MOVE. ** §3.2's
  # catch-up share is what the rule asks of THIS period — what is still missing over the periods
  # left — so it falls as a fund fills, rises when the fund is raided, and prices an overdue bill at
  # its whole amount because `#periods_left` floors at one. Every one of those is right for a row and
  # wrong for §9's verdict about the shape of a budget: a $600 bill anchored a month ago and unpaid
  # fired "your budget doesn't fit your income", and PAYING it cleared the verdict without a rule
  # changing. `#standing_ask` is constant for a given rule and grid; `#planned_this_period` stays
  # exactly where it belongs, on the row and in the adjust panel.
  #
  # ** BEFORE THAT IT WAS `BudgetCalculator`, AND THAT CLASS DIED HERE (fix wave — MED-3). ** Task 4
  # deleted the distribution it belonged to; this one branch kept it alive, and with it a SECOND due
  # date the claims overrule. Two defects, both measured:
  #
  #   THE FULFILMENT LIE. `BudgetCalculator#fulfilled?` has no payment signal for an ITEM-LESS rule,
  #     so it fell back to "assume every bill was paid on time" — `today >= anchor_date` — and priced
  #     such a rule at $0.00 a period while its own row on the same page read `overdue · was Aug 1`.
  #     A one-time rule's standing cost does not depend on whether it has been paid at all now, so
  #     the contradiction cannot come back from either side.
  #   THE FENCEPOST. `periods_until_due` counted from `today` and missed the boundary today stands
  #     on; the divisor here counts the accrual start's own period, because §3.2's accrual lands IN
  #     FULL the day a period opens (spec §10.1 ruling 7).
  #
  # THE FLOOR AT ONE PERIOD LIVES IN `#periods_to_fund`, so a bill due inside the period it was
  # written in — and a user with no declared cadence, whose `period_boundaries` is empty — gets the
  # whole amount asked of one period rather than a division by zero. Blunt, and it is the honest
  # answer: without a period there is nothing to spread over.
  def one_off_steady_ask(today)
    claim_calculator(today: today).standing_ask
  end

  # A RULE BELONGS TO A CATEGORY, full stop (two-ledger spec §3). Its ancestor
  # `#must_have_an_owner` accepted a pool OR a category while both lanes existed, and
  # `#exactly_one_owner` before that refused a record naming both — three shapes of one rule, and
  # the last of them is the one the schema now enforces on its own with `NOT NULL`.
  #
  # BEHIND `#category_mode?` RATHER THAN `belongs_to … optional: false`, and the gate is the whole
  # reason this is a method: two specs plant rules through this model against a schema rewound past
  # the column (see `#category_column?`), and a presence rule that READS a missing attribute raises
  # instead of rejecting. A rewound rule is owner-less and nothing here pretends otherwise; it is
  # simply not asked, exactly as its three siblings are not.
  #
  # ON `:base` RATHER THAN `:category`: an owner-less rule is a fact about the whole record, not
  # about a control the form offers. `budgets/_form` renders `errors[:base]` in its own
  # notification, and the control it offers is a CATEGORY picker, so the sentence describes the
  # form the user is looking at.
  def must_have_a_category
    return unless category_column?

    errors.add(:base, "must belong to a category") unless category_mode?
  end

  # A RULE ON A CATEGORY THAT CANNOT HOLD MONEY AT ALL. Income lands in AVAILABLE and is allocated
  # out of it — an income
  # category holds nothing, ever — so a funding rule on one is a standing claim on money no
  # `Category#holder?` can ever be true of.
  #
  # IT CLOSES A PATH `BudgetProposal` ALREADY CLOSED FROM THE OTHER END, AND THE GAP BETWEEN THE TWO
  # IS THE WHOLE REASON THIS EXISTS. Accepting a rule stamps `funded_since`, and
  # `Category#only_expenses_hold_money` refuses that stamp on an income category — so `POST /budgets`
  # was answered. `PATCH /budgets/:id` is not: `#update` writes `budget.update(budget_params)`
  # directly, never through `BudgetProposal`, so re-parenting a rule onto the user's own income
  # category saved clean. The rule then counted into `Budget.steady_need` (measured: $500 a period
  # of a claim nothing can fill), rendered a group on the Budget page, and was UNFILLABLE FOREVER —
  # `Category.in_fill_order` is holders, so no distribution could ever reach it and no reorder could
  # include it. A validation is the right layer for that: it is a fact about the record, not about
  # which of two writers reached it.
  #
  # `income?` RATHER THAN `!expense?`, matching the enum's own two arms — a third type added later
  # is a decision somebody has to make about this rule rather than one this line makes silently by
  # refusing everything it does not recognise.
  def category_must_be_an_expense
    errors.add(:category, "must be an expense category") if category&.income?
  end

  # ** `#build_up_must_be_valid` IS DELETED WITH THE COLUMNS IT REFEREED (two-shapes spec §7). ** It
  # said two things: `carries-over` may not sit beside an `anchor_date` (a dated rule's build-up is
  # already defined by its date, and `ClaimCalculator#shape` would have had two answers), and a
  # `target-amount` needs a rule whose money builds up (a cap on money that resets is a number no
  # formula reads). Both were about the pair of columns `TwoShapes` drops; with one shape column left
  # there is no pair to referee. `#shape_must_be_valid` below is untouched — it is the CADENCE
  # cascade, about the three columns that say how often a rule comes round, which is a different
  # question and always was.

  # See docs/superpowers/specs/2026-08-14-envelope-budgeting-design.md §3.1
  def shape_must_be_valid
    if basis_per_period?
      errors.add(:basis, "per-period rules cannot have a due date or interval") if anchor_date.present? || interval_months.present?
      return
    end

    return if anchor_date.present?

    # Row 2 pins the anchorless monthly rate rule to a 1-month interval. Any
    # N > 1 is row 3, which requires an anchor — without one the calculator reads
    # the due date as the end of this month and demands N months of money now.
    if interval_months.blank?
      errors.add(:interval_months, "is required for a monthly rule with no due date")
    elsif interval_months != 1
      errors.add(:interval_months, "must be 1 for a monthly rule with no due date")
    end
  end

  def category_column? = has_attribute?(:category_id)

  def keeps_column? = has_attribute?(:keeps_unspent)

  # ** "KEEPS WHAT IT DOESN'T SPEND" IS A PER-PERIOD ANSWER, AND A DUE DATE IS THE OTHER ONE
  # (two-shapes spec §12). ** A dated rule's unspent money is already defined by its date: the walk
  # holds it until the day and empties it when the bill is paid. Setting both columns would give
  # `ClaimCalculator#shape` two answers about one rule — the exact pair `#build_up_must_be_valid`
  # refereed before `TwoShapes` dropped its columns — so the combination is refused rather than
  # ranked.
  #
  # ON `:anchor_date`, WHICH IS THE COLUMN THE FORM'S "When is it needed?" RADIO WRITES:
  # `RuleForm::BUDGET_ERROR_FIELDS` routes that attribute to `:schedule`, so the sentence lands
  # under the control that chose the date rather than under a checkbox the form hides on that path.
  # Unreachable from the form itself (`RuleForm#schedule_columns` writes `keeps_unspent: false` on
  # every dated rule, and the checkbox is disabled and cleared under "By a date"); this is the answer
  # to a hand-made POST and to any later writer that assigns the columns directly.
  def keeps_unspent_never_dates
    return unless keeps_unspent? && anchor_date.present?

    errors.add(:anchor_date, "cannot be set on a rule that keeps what it doesn't spend")
  end

  # A dated bill anchors on an item, and that item has to be an item OF the category the rule funds
  # — an item from somewhere else would date a bill against money it never drains.
  #
  # Objects, not ids: under `build` nothing is persisted and `nil == nil` would wave every
  # item-less category through.
  def item_must_belong_to_category
    return if item.blank?

    errors.add(:item, "must belong to this category") unless item.category == category
  end

  # ** ONE CATEGORY, ONE BUDGET LINE (two-ledger spec §3), NOW THAT THE LINE IS A CLAIM (Henry's
  # ruling of 2026-09-03). ** An ITEM-LESS rule's spending lane is the WHOLE category — that is
  # computed-claims §3.2's own sentence, "an expense on the rule's item, or, for an item-less rule,
  # on the category" — and `Category#claim` is the SUM of its rules' claims. So two item-less rules
  # on one category each subtract the same entries: $250 of groceries comes off a $400 rate rule and
  # off a $75 one beside it, and the category reports $225 claimed when the honest figure is $475
  # less one $250. Neither rule is wrong on its own, which is what makes it invisible.
  #
  # ITEM-BACKED RULES STAY PER-ITEM and are untouched: their lanes are disjoint by construction, and
  # `#item_must_not_be_claimed` below already keeps two rules off one item. A category may therefore
  # carry one catch-all rule and as many dated bills as it has items, which is exactly the demo's
  # shape and Ming's.
  #
  # ON `:base`, with `#must_have_a_category`'s reasoning: it is a fact about the whole record rather
  # than about one control, and `budgets/_form` renders `errors[:base]` in its own notification. The
  # sentence names both ways out, because both are things the user can actually do on that form.
  #
  # `where.not(id: id)` for `#item_must_not_be_claimed`'s reason: it renders as `id IS NOT NULL` on
  # an unsaved record, so a new rule is compared against every persisted one, and an edit does not
  # collide with itself.
  def category_may_hold_one_item_less_rule
    return if item_id.present?
    return unless Budget.where(category_id: category_id, item_id: nil).where.not(id: id).exists?

    errors.add(:base, CATCH_ALL_TAKEN)
  end

  # ** `#set-aside-only` IS DELETED (two-shapes spec §7). ** It named the one shape that could
  # demand nothing — a dateless target fed only by positive adjustments, whose amount of zero was how
  # "no standing rate" was spelled — and it gated the two `amount` numericality rules against each
  # other. A goal names a day now, so `amount > 0` is unconditional above and there is nothing left
  # for the exemption to exempt.

  # `where.not(id: nil)` renders as `id IS NOT NULL`, so an unsaved budget still
  # compares against every persisted rule. An unsaved *item* has no id though,
  # and `item_id: nil` would match every item-less budget — bail rather than
  # invent a conflict.
  def item_must_not_be_claimed
    return if item&.id.blank?

    claimed = Budget.where(item_id: item.id).where.not(id: id).exists?
    errors.add(:item, "is already used by another rule") if claimed
  end
end
