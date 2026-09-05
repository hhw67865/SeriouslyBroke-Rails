# frozen_string_literal: true

# THE DEMO, ON COMPUTED CLAIMS (computed-claims spec §§2-4).
#
# WHAT THIS FILE MAY WRITE, AND WHAT IT MAY NOT. Post-drop shapes only: bank ACCOUNTS, expense and
# income CATEGORIES, funding RULES on categories, dated ADJUSTMENTS on those rules (the purpose
# side's only writer besides the rules themselves), ACCOUNT MOVEMENTS (the physical ledger), income
# routing, entries, a declared period and a typical income. There is no envelope, no goal pool, no
# `categories.pool_id`, no paid-from override AND NO ALLOCATION, because none of those columns or
# tables exists any more. `spec/seeds_spec.rb` greps this file for the legacy constructs AND asserts
# the database after a replant, so the two halves of that promise cannot drift apart.
#
# ---------------------------------------------------------------------------------------------
# THE TWO LEDGERS, AND WHERE EACH ONE IS WRITTEN HERE.
# ---------------------------------------------------------------------------------------------
#
#   PHYSICAL — where the money sits, and it is UNCHANGED by the computed-claims plan.
#     `pot (= Checking) + Σ accounts`. Income and expense ENTRIES all belong to the pot; the other
#     three accounts are fed by movements alone, which is what `Entry#route_income_to!` writes when
#     income lands somewhere other than main. `pot + Σ accounts == income − expenses` is the
#     invariant, and `spec/seeds_spec.rb` asserts it on the replanted demo, in raw SQL, against
#     $7,461.00.
#
#   PURPOSE — what the money is FOR, and it is now COMPUTED rather than moved (§2).
#     `free = min( pot , total_money − Σ claims )`. That is a DEFINITION and not a partition: a
#     claim is a function of the rule, the calendar, the category's spending and its dated
#     adjustments (`ClaimCalculator`), so nothing is conserved and there is no second sum for this
#     file to keep in step. The old `available + Σ holdings == total` identity is gone with the
#     movements that made it true, and so is every row that used to record one.
#
# WHAT THE OLD `allocate` ROWS BECAME, AND THE RULING IS THIS FILE'S OWN. Under the pool and
# two-ledger eras every set-aside was a row: the household's savings contributions AND the routine
# funding of every rate rule and every dated bill, all written as `Allocation`. §7 of the
# computed-claims spec splits that population in two and the demo is re-derived along the same line:
#
#   * THE ROUTINE FUNDING OF A RULE IS DISTRIBUTION MECHANICS AND IS SIMPLY GONE. $1,500 into Rent
#     on the day the rent was paid, $460 into Groceries every fortnight, $318 into Utilities, $180
#     into Renters Insurance, $60 into the transit pass, $50 into the Vacation goal: every one of
#     those is now what the rule COMPUTES, and writing it down as well would count it twice. (Not a
#     hypothetical: a +$400 adjustment on the $400 Groceries rate rule reads `claim = 400 + 400 − 0`,
#     an $800 envelope on a $400 rule.)
#   * A HAND SET-ASIDE INTO A GOAL WITH NO RULE OF ITS OWN IS §3.3'S ADJUSTMENT and is converted, at
#     its own date, with its own sign. Four goals on this demo are fed that way and nothing else
#     feeds them.
#
# THE MIGRATION'S OWN PREFLIGHT DRAWS THE SAME LINE, which is why the two land on one shape.
# `DropTheDistribution#unfundable_ends` REFUSES a conversion onto a category with no item-less rule
# and no target — Rent, Utilities, Commuter Pass and Renters Insurance are all exactly that (their
# only rule names an item), so those rows could not have been converted even in principle. What it
# DOES convert is a set-aside onto a category that either lends a catch-all rule or can be given
# one, and `#mint_rule` mints the target-only shape for precisely the four goals below.
#
# ---------------------------------------------------------------------------------------------
# EVERY RULE IS BORN ON `demo_start`, AND THAT IS THE ACCRUAL-SPAN RULING (§3.2).
# ---------------------------------------------------------------------------------------------
#
# `ClaimCalculator#accrual_start` is `max(category.funded_since, the rule's own birthday)` — a rule
# cannot accrue before it existed — and `#countable_span` is the days that walk visits. A rule
# created by the seed run itself is born TODAY, so it would walk exactly one period: every fund on
# this demo would read $0.00 built up the moment it was planted, and every set-aside dated three
# months back would land outside the span and move no figure on any screen.
#
# THE CHOICE IS THE MIGRATION'S, NOT A RE-DATING OF THE HISTORY. `DropTheDistribution#birthday_for`
# backdates a minted rule's `created_at` to the category's `funded_since` for this exact reason, and
# every rule here is stamped the same way: born on `demo_start`, the day every holder started
# holding. So `accrual_start` lands on `funded_since` — §7's "rules and `funded_since` stay and
# become the accrual anchors" — and the six months of history below is history the claims can see.
# The alternative, dating every set-aside inside the current period, was rejected: it would put
# seven periods of savings on one afternoon, which is a false sentence about when the household
# saved and would make `Vacation to Europe`'s and `Emergency Fund`'s rows read as a windfall.
#
# ---------------------------------------------------------------------------------------------
# THE SCREEN STATES ARE THE DELIVERABLE, AND THE TABLE IS BELOW rather than in a scratch report
# that is not in the repository. Every figure is one OBSERVED after a replant, not one reasoned to.
# ---------------------------------------------------------------------------------------------
#
#   HOME'S HERO (answers-first §§2-3 on computed terms). `free` is negative here, and that is this
#   demo's inheritance from the pool era rather than a new pessimism: the old table led with
#   "available $1,900.00 against more than that in asks, so the cutoff is drawn", and the household
#   whose rules outrun its money renders that same fact as §4's shortfall now that there is no
#   waterfall to draw a cutoff on.
#
#     In Checking            $5,561.00   the pot — `AccountLedger#pot`, main's balance
#     Free to spend        -$13,557.56   `pot − Σ claims` (two-shapes §2), unclamped
#     Claimed              $19,118.56    Σ over all 19 rules
#     total money            $7,461.00   pot + the three other accounts ($1,900.00), SHOWN and never
#                                        subtracted — the hero says it in its own clause
#
#   ** THE FREE FIGURE MOVED FROM -$2,740.34 TO -$13,557.56 AND THE TWO SHAPES ARE WHY (§2). ** Two
#   changes compound. The cap is gone, so money in the three other accounts no longer offsets a
#   claim — worth $1,900. And the three GOALS are dated rules now: a fund with no deadline asked
#   nothing of a period and held only what the household set aside, while "$50,000 by Jan 1 2031"
#   asks `remaining ÷ periods left` every period from the day it was written. Six months in, the
#   three of them have accrued $12,762.22 between them where the five old funds held $2,795.
#
#   THE TROUBLE STRIP (§4), and this demo lights four of its five arms:
#     :overdraft   Side Gig Checking is overdrawn $300.00
#     :shortfall   $13,557.56 short, at $1,042.89 a day for the thirteen days left, and the give-way
#                  walk BY TYPE AND THEN BY REVERSE PRIORITY (rules-own-the-budget §3):
#                    choice  Vacation to Europe $1,965.77 · Holiday Gifts $933.34 · Streaming $25.00
#                    usage   House Down Payment $6,578.50 · Medical Copays $60.00 ·
#                            Commuter Pass $60.00 · Pet Care $50.00 · Household Supplies $75.00 ·
#                            Groceries $400.00 · Utilities $120.00 — the Electric Bill is typed
#                            `usage` though it is dated, which is the row that keeps the type from
#                            being a synonym for the schedule
#                    bill    Emergency Fund $3,289.95 — PARTIAL, which is the shape a walk can say
#                            and a filter cannot; the rent is never reached at all
#                  ** THE TYPE IS STILL WHAT ORDERS IT, and it is more visible than it was: every
#                  `choice` rule goes before any `usage` one and every `usage` one before any
#                  `bill`, so the household's $50,000 house deposit gives way ahead of its $400
#                  groceries and the emergency fund is the last thing reached. Under priority alone
#                  the goals would have led the list in a different order entirely.
#     :over        Dining Out — over by $10.00
#     :overdue     Renters Insurance — was due 6 days ago, $180.00 built up of $180.00, all there
#     :structural  rules need $2,858.18 a period against a declared $2,050.00 — the standing ask of
#                  every rule (`Budget.steady_need`), which for a one-off is the amount spread from
#                  the day the rule was born to the day it falls due and moves with nothing else
#                  (fix wave 2 — MED-A). It read $2,103.42 while the three goals asked NOTHING of a
#                  period; a goal that names a day states its cost, which is the ruling's point.
#
#   "THIS PERIOD" (§3.4), one row per category and one line per rule. The period ANCHORS ON TODAY,
#   so today is the only day of it that has happened — a rate row reads $0.00 unless its money went
#   out this morning, which is the honest first-day shape and is why the two rows that carry a
#   figure carry a same-day entry:
#
#     RATE, UNDER      Household Supplies   $45.00 of $120.00       today's detergent run
#     RATE, OVER       Dining Out           $110.00 of $100.00      red, `over by $10.00` beneath
#     RATE, UNTOUCHED  Groceries            $0.00 of $400.00        the period opened this morning
#     ACCRUING         Rent                 $1,500.00 built up of $1,500.00 · next due <today+10>
#     ACCRUING         Car Insurance        $1,050.00 built up of $1,200.00 · next due <today+1mo>
#                                             · $75.00 per period
#     ACCRUING         Quarterly Taxes      $1,400.00 built up of $1,800.00 · next due <today+2mo>
#                                             · $100.00 per period
#     OVERDUE          Renters Insurance    $180.00 built up of $180.00 · was due <today-6>
#     GOAL             Vacation to Europe   $1,965.77 built up of $5,000.00 · next due Jun 1, 2027
#                                              · $159.70 per period
#     GOAL             Emergency Fund       $4,217.95 built up of $10,000.00 · next due Sep 1, 2027
#                                              · $235.28 per period — its catch-up plus seven $100
#                                              set-asides, which is the change of shape in one row
#     UNRULED          Transportation       spent $48.00            no rule, no bar, no pressure
#
#   THE BUDGET PAGE — the same two sentences, per rule, beside what the rule SAYS:
#     `$400.00 per period · $0.00 of $400.00`                       Groceries
#     `$1,800.00 every 3 months · $1,400.00 built up of $1,800.00 · next due <today+2mo> ·
#      $100.00 per period`                                          Quarterly Taxes
#     and one band under the give-way order: "1 rule counting no spending" — Streaming, whose
#     category has no holding date, so its $25.00 claims every period while nothing spent there
#     ever comes off it.
#
#   THE DASHBOARD'S SAVINGS STRIP composes `Budget.saving_toward_a_date` — an item-less rule with an
#   anchor and no interval (two-shapes §2) — so the three goals below appear on it and no bill does:
#   House Down Payment $6,578.50 of $50,000.00, Emergency Fund $4,217.95 of $10,000.00 and Vacation
#   to Europe $1,965.77 of $5,000.00, $12,762.22 claimed between them. All three are claims and none
#   is money moved. The classifier has been a figure on the CATEGORY and then the rule whose unspent
#   money carried; it is the DATE now, which is also what keeps the six-monthly car insurance off a
#   strip about saving.
#
#   THE BUDGET PAGE'S TYPE OVERVIEW (§3), summed from `Budget#steady_ask` over all 19 rules:
#     `Bills $1,393.30 · Usage $1,142.21 · Choice $322.67 a period` — which adds to the $2,858.18
#     `Budget.steady_need` reports, because it is the same sum partitioned three ways. Every one of
#     the three goals is inside it now: the emergency fund's $256.41 lands in Bills, the house
#     deposit's $396.83 in Usage and the vacation's $151.52 in Choice, where the old funds asked
#     nothing of a period at all.
#
#   WHICH TYPE EACH RULE CARRIES, and the table is here because nothing else in the file can say it
#   in one place. Henry's definitions (§3): bill "must be paid", usage "a real need whose amount
#   moves with how you live", choice "discretionary".
#
#     bill    Rent · Dentist · Car Insurance · Vet · Renters Insurance · Quarterly Taxes ·
#             Prescriptions · Emergency Fund
#     usage   Utilities/Electric · Groceries · Household Supplies · Pet Care · Commuter Pass ·
#             Medical Copays · House Down Payment
#     choice  Dining Out · Holiday Gifts · Streaming · Vacation to Europe
#
#   THE ELECTRIC BILL IS `usage` THOUGH IT HAS A DUE DATE, and it is the row that keeps the type
#   from being a synonym for the schedule: "usage is like power bill (can be lowered by adjusting
#   life)" is Henry's own example of the word. The migration's default types every dated rule `bill`
#   (§6 step 3) precisely because it cannot know that; the demo shows the corrected reading.
#
#   THE FOUR SUGGESTION DETECTORS, and the categories that feed each. `SuggestionEngine` reads
#   ENTRIES and RULES and never read an allocation, so the drop moved none of these:
#     dated_bill (3)  the utility items carrying no rule of their own (Phone, Internet, Water),
#                     each offering to JOIN the Utilities category — the reuse branch.
#     rate (4)        Transportation, Shopping, Personal Care, Entertainment — the categories that
#                     hold nothing, so their spending reads straight against free
#     drift (4)       Groceries (the one UPWARD suggestion, $460 spent against a $400 rule),
#                     Dining Out, Household Supplies, Pet Care
#     dead_rule (1)   Commuter Pass — the fortnightly pass stopped five periods ago
#
#   ONE DELIBERATE $0.00 DRIFT, AND IT IS THE BRANCH THE DETECTOR'S OWN HEADER ASKS FOR. Household
#   Supplies spent nothing in the four complete periods the drift window measures and $45.00 today,
#   so the panel says "averaged $0.00 for 4 periods, your rule says $120.00" — `SuggestionEngine
#   #drift_suggestion`'s second half, "the funded category that quietly stopped", which no other
#   detector can report. The pool era's objection stands against FOUR of them on categories nobody
#   had spent from YET; one, on a category whose spending really did stop, is the sentence.
#
#   THE THREE ACCOUNTS THAT ARE NOT THE POT, and what each one is for on Home:
#     Ally Savings        +$1,800.00  three routed transfers — the ordinary second account
#     Health Savings        +$400.00  two payroll contributions straddling the period boundary
#     Side Gig Checking     -$300.00  OVERDRAWN, which the trouble strip has a line for:
#                                     $1,300 of invoices routed in, $1,600 moved back to Checking
#                                     to pay the quarterly tax bill from the pot
#
# NO `rand`, ANYWHERE. Every figure here is written down, so a replant lands on the same balances
# without a seeded PRNG to remember.
#
# EVERY DATE IS RELATIVE TO THE RUN DAY, AND THE STATES HOLD ON ANY RUN DAY. The period is declared
# biweekly and anchored on today, so today opens a period and `today - 14n` is the boundary n
# periods back. The suggestion engine measures in COMPLETE periods (the six ending yesterday), and
# the entries below are placed inside named periods rather than inside calendar months for exactly
# that reason. The bills that must look monthly — the rent, the four utility items — step by
# `n.months` from today instead, which is a whole number of months apart on every run day, and they
# are all dated at least 24 days back so no run day can slide one of them past the Utilities anchor.
#
# THE ZONE IS SET BEFORE THE FIRST RECORD IS SAVED, and it has to be.
#
# `entries.date`, `adjustments.date` and `account_movements.date` are DATETIME columns, so
# ActiveRecord casts the Date handed to `date:` through `Time.zone` — which in a rake process is the
# application default, UTC, because config/application.rb never sets one. Every date-bounded query
# in the app resolves in the REQUEST zone instead: ApplicationController wraps each request in
# `Time.use_zone(current_user.timezone)`, `User#period_datetimes_containing` widens its range with
# `Date#beginning_of_day`, and `Adjustment#local_day` re-zones a delta into the period CONTAINING
# its date. Seeded without this line, the demo user's paycheck — dated `today`, the day the period
# opened — was stored as 00:00 UTC and read back as 20:00 the PREVIOUS evening in New York, four
# hours before its own period began, and the screen reported `Income this period $0.00` beside it.
#
# A local rather than a constant: seeds.rb is `load`ed, and `bin/ci` runs it more than once in a
# session, so a constant here would warn about being reinitialised.
demo_timezone = "America/New_York"
Time.zone = demo_timezone

# DELETE IN FOREIGN-KEY ORDER, AND THE PURPOSE SIDE COMES FIRST. `adjustments.rule_id` is a
# NON-CASCADING key to `budgets` (schema.rb: `add_foreign_key "adjustments", "budgets", column:
# "rule_id"`), so a surviving adjustment makes `Budget.delete_all` raise; `dependent: :destroy` on
# `Budget#adjustments` does not help, because `delete_all` runs no callbacks. `account_movements`
# has non-cascading keys to `pools` and to `entries`, so it goes ahead of both.
#
# `allocations` IS NOT ON THIS LIST BECAUSE THE TABLE IS GONE (§5, `DropTheDistribution`). It used
# to lead the list for the same reason `adjustments` does now.
#
# `Budget` COMES BEFORE `Item`: `budgets.item_id` is a non-cascading foreign key, so an item-backed
# funding rule pins its item — with `Item` ahead of `Budget` this loop raised
# `PG::ForeignKeyViolation ... on table "budgets"`. It is invisible under `db:seed:replant`, which
# TRUNCATES first; `bin/setup`'s plain `db:seed` is the path that breaks.
#
# `users.default_account_id` nullifies on pool delete, so User can come last.
Rails.logger.debug "Clearing existing data..."
[AccountMovement, Adjustment, Entry, Budget, Item, Category, Pool, User].each do |model|
  Rails.logger.debug { "Deleting #{model.name} records..." }
  model.delete_all
end

Rails.logger.debug "Creating the demo user..."
user = User.create!(
  email: "demo@example.com",
  password: "password123",
  name: "Demo User",
  timezone: demo_timezone
)

# THE USER'S OWN TODAY, NOT `Date.current`. Every request runs inside the user's timezone
# (ApplicationController sets it) and every claim reader takes the OWNER's day (`User#today`), so
# Home computes against the New York date while a seed run late in the evening computes against the
# UTC one — a day apart. Seeded with the UTC date, the Dentist bill below anchored a day late and
# the period boundary landed INSIDE its window, so the category that state exists to demonstrate
# rendered as something else entirely.
today = Time.find_zone!(user.timezone).today

# THE ANCHOR IS TODAY, so today is a period boundary and the current period is `today..today+13`.
# Three things follow, and all three are load-bearing. The Dentist bill three days out is genuinely
# unreachable — no boundary falls between tomorrow and its due date. Every complete period the
# suggestion engine measures in is exactly `today - 14n .. today - 14(n-1) - 1`. And TODAY IS THE
# ONLY ELAPSED DAY OF THE CURRENT PERIOD, which is why every "spent this period" figure on the
# state table above belongs to an entry dated `today` and every other rate row reads $0.00: a rate
# claim is `max(0, rate + Σ this period's deltas − this period's spending)` (§3.1) and this period
# is one morning old.
#
# `typical_income` is what the user SAYS they bring in, and it is UNDER the $2,600 paycheck below on
# purpose: it is a declaration, not a measurement, and §9's structural check compares it against
# `Budget.steady_need` — $2,858.18 here — so the demo is structurally underwater and the sacrifice
# view has a screen. That screen existing is the load-bearing property; the exact gap is not.
#
# ** IT WAS $2,400 AGAINST A NEED OF $2,459.99 (fix wave — MED-3). ** `Budget#steady_ask`'s one-off
# branch used to divide the WHOLE amount by the periods left before the due date, and it built a
# `BudgetCalculator` to do it — a class that also assumed every item-less bill was paid on time.
# The need fell $356.58 when that class died, so the declaration followed it down to keep the state
# this seed exists to show.
#
# ** FIX WAVE 2 (MED-A) MOVED IT BY ONE CENT, AND THE CENT IS WORTH THE SENTENCE. ** The one-off
# branch is `ClaimCalculator#standing_ask` now — the amount over the periods from the rule's birth to
# its due date, constant — rather than §3.2's catch-up share, which moves with the fund. On THIS
# household the two agree almost exactly, because both one-time bills (the $300 Dentist visit and the
# $180 Vet bill) were born with the rest of the seed and have had nothing spent against them: only
# the Dentist's rounding differs, $21.43 a period against $21.42, because the standing figure divides
# and rounds ONCE while catch-up rounds every period it walks. $2,103.41 → $2,103.42, and the demo
# stayed $53.42 a period underwater against the same declared $2,050.
#
# ** THE TWO SHAPES TOOK IT FROM $53.42 TO $808.18 (two-shapes §2), AND THE DECLARATION DOES NOT
# FOLLOW IT THIS TIME. ** The three goals are dated rules now, so each states what it costs a period
# — $256.41, $396.83 and $151.52 — where the funds they replace asked NOTHING of one. That is the
# ruling's whole point ("build up is just a higher target on a timeline longer than a period"), and
# the honest demo is a household whose goals it cannot actually afford at those dates. The
# declaration stays at $2,050 because it is what the user SAYS they bring in, and moving it to hide
# the gap would be the seed lying about the state it exists to show.
user.update!(period_cadence: :biweekly, period_anchor_date: today, typical_income: 2_050)

# ---------------------------------------------------------------------------------------------
# Builders. Every record below goes through one of these, so a shape this demo may not write has
# nowhere to come from.
# ---------------------------------------------------------------------------------------------

# n periods back from today, on the boundary. The period that opened here closed on
# `periods_ago[n - 1] - 1`, which is the window the engine's detectors measure in.
periods_ago = ->(n) { today - (n * 14) }

account = ->(name) { user.pools.create!(name: name, pool_type: :account) }

# EVERY HOLDER STARTED HOLDING BEFORE THE HISTORY BELOW, and that is the funding-start rule
# (two-ledger spec §4, kept by §7) rather than decoration. A category counts its own spending only
# from `funded_since` on; earlier spending drains FREE. A demo whose categories all started today
# would push its entire seeded history onto the root and open every fund empty. Thirteen periods
# clears the deepest thing this file writes (three calendar months of rent, seven biweekly periods
# of paychecks), so every entry below lands where the sentence around it says it does — and it is
# the day every RULE is born on too, which is what lets a claim walk that history (see the header).
#
# ** THIRTEEN PERIODS AND NOT `today - 6.months`, AND THE DIFFERENCE IS WHETHER THE STATE TABLE
# HOLDS ON EVERY RUN DAY. ** The two are within three days of each other, but `6.months` is 181 to
# 184 days depending on which months it spans, and `ClaimCalculator`'s walk opens at
# `user.period_containing(accrual_start)` — so at 184 days back the walk visits FIFTEEN periods and
# at 181 it visits fourteen. Every accruing figure on the demo is a sum over those periods:
# measured, `Vacation to Europe` read $570.00 on a fifteen-period run and $520.00 on a fourteen under
# the shape that preceded the dated one, and
# a header table naming either would be wrong on most mornings of the year. A boundary is a fixed
# number of periods back by construction, so the walk is fourteen periods on every run day and the
# figures below are facts rather than coincidences.
demo_start = periods_ago[13]

# A CATEGORY THAT HOLDS MONEY — `Category#holder?` is `expense? && funded_since.present?`, and this
# is the only builder that stamps the column. `priority` survives as the GIVE-WAY order (§4): the
# same ranking read for the opposite question, which category yields first when the money runs out.
holder = lambda do |name, priority, color|
  user.categories.create!(
    name: name,
    category_type: :expense,
    color: color,
    funded_since: demo_start,
    priority: priority
  )
end

# A CATEGORY THAT HOLDS NOTHING: no `funded_since`, so its spending is attributed to no envelope at
# all and reads straight against `free`. This is what the app means by "it comes out of what's
# available", and it is the population the rate detector proposes rules for.
lane = lambda do |name, type, color|
  user.categories.create!(name: name, category_type: type, color: color)
end

# ** A FUNDING RULE, BORN ON `demo_start`. ** The one builder every rule goes through, and the
# `created_at` is the whole reason it exists rather than sixteen bare `Budget.create!` calls each
# carrying the same subtle column. See the header: `ClaimCalculator#accrual_start` is
# `max(funded_since, the rule's birthday)`, so a rule born at seed time walks one period and every
# fund on the demo reads empty.
#
# Rails only stamps `created_at` when it is nil, so passing it here is the whole of the override.
rule = ->(**attributes) { Budget.create!(created_at: demo_start, **attributes) }

log = lambda do |item, amount, on, description|
  item.entries.create!(amount: amount, date: on, description: description)
end

# INCOME THAT LANDED SOMEWHERE OTHER THAN MAIN. The entry itself always belongs to the pot — income
# lands in the pot and claims are computed over it — and this writes the ONE mirroring transfer that
# says the cash physically went elsewhere, exactly as the entry form does.
deposit = lambda do |item, amount, on, description, into|
  log.call(item, amount, on, description).tap { |entry| entry.route_income_to!(into) }
end

# ** MONEY SET ASIDE BY HAND — ONE DATED, SIGNED DELTA ON ONE RULE (§3.3). ** `accrued(P) =
# planned(P) + Σ adjustments dated inside P`, so a positive row raises the accrual of whatever
# period contains its date and a negative one lowers it. This is the only purpose-side WRITE left in
# the app, and it replaces `allocate` — which wrote an `Allocation` row from NULL (available) into a
# category, on a table that no longer exists.
#
# ** IT FINDS THE CATEGORY'S ITEM-LESS RULE AND RAISES IF THERE IS NONE, which is §3.3's "every
# adjustment targets a rule" made unskippable. ** The catch-all rule is the one whose spending lane
# is the WHOLE category (§3.1's partition), which is the lane money is set aside for; a category may
# carry at most one (`Budget#category_may_hold_one_item_less_rule`), so `find_by!` is a total
# lookup rather than a first-of-many. `DropTheDistribution#resolve_rules` performs the same lookup
# against real data and mints the rule where there is none — which is what the four goals below do
# for themselves, in the same target-only shape.
set_aside = lambda do |category, amount, on|
  # ** THE SEEDS WRITE `Adjustment` DIRECTLY AND THAT IS ACCEPTED (fix wave — LOW-7). ** Every
  # adjustment a USER makes goes through `AdjustmentForm`, the one typed door, which refuses a date
  # the rule's walk cannot count (§3.3; spec §10.2 ruling 11). These rows are not typed: they are a
  # history being planted, dated deliberately across the periods the demo's rules have lived
  # through, and the form's span check is exactly the thing that would refuse them — the same
  # reasoning §7's migration converts a user's real history at its ORIGINAL dates on. The model's
  # own validations still apply; what is bypassed is the door's opinion about WHEN, which a seed
  # writing the past is entitled to hold.
  Adjustment.create!(rule: Budget.find_by!(category: category, item_id: nil), amount: amount, date: on)
end

# MONEY CROSSING BETWEEN TWO OF THE USER'S OWN BANK ACCOUNTS. Net worth is unchanged and no
# category is involved: this is location, not intention.
move = ->(from, to, amount, on) { AccountMovement.create!(from_pool: from, to_pool: to, amount: amount, date: on) }

# ---------------------------------------------------------------------------------------------
# THE ACCOUNTS. Four, and only Checking holds entries — the other three are movement-fed, which is
# what the physical ledger says an account is (§2).
# ---------------------------------------------------------------------------------------------
Rails.logger.debug "Creating the four accounts..."

checking = account.call("Checking")
ally = account.call("Ally Savings")
side_gig = account.call("Side Gig Checking")
health_savings = account.call("Health Savings")

# THE ACCOUNT THE DEMO NOMINATES. `users.default_account_id` IS the pot: every entry the household
# records lands there, and `Entry#route_income_to!` mirrors out of it. Nominated explicitly rather
# than left to whichever account happens to sort first.
user.update!(default_account: checking)

# ---------------------------------------------------------------------------------------------
# THE HOUSEHOLD'S BILLS AND RUNNING COSTS. Priorities 1-9, which is the order they GIVE WAY in when
# the money runs out — read from the bottom (§4).
# ---------------------------------------------------------------------------------------------
Rails.logger.debug "Creating the holders and their rules..."

rent = holder.call("Rent", 1, "#E57373")
utilities = holder.call("Utilities", 2, "#FFD54F")
dentist = holder.call("Dentist", 3, "#F48FB1")
car_insurance = holder.call("Car Insurance", 4, "#9575CD")
dining = holder.call("Dining Out", 5, "#81C784")
groceries = holder.call("Groceries", 6, "#8BC34A")
supplies = holder.call("Household Supplies", 7, "#90A4AE")
pet_care = holder.call("Pet Care", 8, "#A1887F")
commuter = holder.call("Commuter Pass", 9, "#7986CB")

rent_item = rent.items.create!(name: "Monthly Rent")
electric_item = utilities.items.create!(name: "Electric Bill")
phone_item = utilities.items.create!(name: "Phone")
internet_item = utilities.items.create!(name: "Internet")
water_item = utilities.items.create!(name: "Water")
restaurants = dining.items.create!(name: "Restaurants")
supermarket = groceries.items.create!(name: "Supermarket")
cleaning = supplies.items.create!(name: "Cleaning & Paper Goods")
pet_food = pet_care.items.create!(name: "Pet Food")
vet = pet_care.items.create!(name: "Vet")
transit_pass = commuter.items.create!(name: "Transit Pass")

# A FUND BUILDING UP TOWARD A DATE (§3.2) — the rent, whole, ten days before it is due. ITEM-BACKED,
# so a payment on the Monthly Rent item is the FULFILMENT that drops the fund and rolls the cycle;
# the three payments below are all before this anchor, so nothing has rolled and the next occurrence
# is ten days out. The anchor is ten days out rather than on a calendar day, so the state does not
# depend on where in the month the seeds are run.
rule.call(
  category: rent,
  item: rent_item,
  amount: 1_500,
  interval_months: 1,
  anchor_date: today + 10,
  rule_type: :bill
)

# THE SAME SHAPE ON A SHORTER LEASH, and the reason the electric bill is not the demo's OVERDUE row.
# `ClaimCalculator#due_on` rolls the cycle on PAYMENT, counted as `min(paid ÷ target, cycles
# elapsed)`: three $120 bills have been paid since `demo_start`, so one whole cycle is settled and
# the next occurrence is a month past this anchor — in the future, and the row reads as accruing
# toward it. Renters Insurance below is the row whose date really did pass unpaid.
rule.call(
  category: utilities,
  item: electric_item,
  amount: 120,
  interval_months: 1,
  anchor_date: today - 10,
  rule_type: :usage
)

# A ONE-TIME BILL, THREE DAYS OUT, with no period boundary between tomorrow and then. Under the
# distribution this was the `won't make it` state — no future funding could reach it. There is no
# funding step to miss now: §3.2's catch-up formula has been accruing toward it since `demo_start`,
# so the fund is simply there, and what the row says is the date.
rule.call(category: dentist, amount: 300, anchor_date: today + 3, rule_type: :bill)

# A SIX-MONTHLY PREMIUM ONE MONTH OUT — the longest catch-up on the demo, and the row whose
# `$X per period` clause is worth reading: the share is recomputed every period from what is still
# owed and how many periods are left, so it is not $1,200 ÷ 13.
rule.call(
  category: car_insurance,
  amount: 1_200,
  interval_months: 6,
  anchor_date: today + 1.month,
  rule_type: :bill
)

# ** A RATE RULE SPENT OVER ITS RATE (§3.1) — the demo's one RED row. ** $110 of dinner against a
# $100 fortnight, so `claim = max(0, 100 − 110)` is zero, the $10 excess came straight out of what
# is free, and `ClaimCalculator#over?` — which reads the figure BEFORE the clamp — is what puts the
# row in red and the line "over by $10.00" under it and in the trouble strip.
#
# THE RULE IS $100 AND NOT THE $150 THE POOL ERA CARRIED, and the change is what makes the state
# reachable at all. A rate claim measures THIS period's spending, this period is one morning old,
# and the only dining money inside it is the $110 dated `today`; at $150 the row would read
# "$110.00 of $150.00" and the demo would have no `over` anywhere. The second dinner stays where it
# was, in the period that closed yesterday, because the DRIFT detector measures the four complete
# periods and a category whose every receipt moved into today would read "averaged $0.00" there.
rule.call(category: dining, amount: 100, basis: :per_period, rule_type: :choice)

# THE RATE RULE NOTHING HAS COME OFF YET — the ordinary shape on the morning a period opens, and the
# one the bar draws at 0%. Its spending runs $460 a period against this $400 rule over the four
# complete periods behind it, which is the drift detector's one UPWARD suggestion: every other drift
# on this demo says cut.
rule.call(category: groceries, amount: 400, basis: :per_period, rule_type: :usage)

# ** A RATE RULE SPENT UNDER ITS RATE ** — $45 of detergent this morning against $120 a fortnight,
# so the claim is the $75 that is left and the row is the only one on the demo that shows a number
# you may actually still spend.
#
# IT IS ALSO THE DELIBERATE $0.00 DRIFT (see the header): the receipt moved into today is the only
# one this category has, so the four complete periods behind it are empty and the panel says
# "averaged $0.00 for 4 periods, your rule says $120.00" — `SuggestionEngine#drift_suggestion`'s
# funded-category-that-quietly-stopped branch, which no other detector can report.
rule.call(category: supplies, amount: 120, basis: :per_period, rule_type: :usage)

# THE MIXED CATEGORY, and it is what §3.1's lane PARTITION exists for: a rate rule whose lane is
# everything in Pet Care EXCEPT the items that carry their own rule, beside a dated vet bill whose
# lane is the Vet item alone. Without the partition the kibble and the vet's fee would come off both
# claims, Σ claims would fall twice for one payment, and `free` would RISE when a bill was paid.
rule.call(category: pet_care, amount: 50, basis: :per_period, rule_type: :usage)
rule.call(category: pet_care, item: vet, amount: 180, anchor_date: today + 20, rule_type: :bill)

# A RULE STILL FUNDING SOMETHING THAT STOPPED — detector 4's only subject on this demo, and the
# one shape the other three cannot report. The household stopped buying the fortnightly transit
# pass five periods ago and the $60 rule is still claiming for it every period: item-backed (an
# item is what makes a rule payable and therefore what can stop) and per-period, so it never
# reads `overdue` and the sentence the panel prints is the whole of what is wrong with it.
rule.call(category: commuter, item: transit_pass, amount: 60, basis: :per_period, rule_type: :usage)

# ---------------------------------------------------------------------------------------------
# ** THE OCCURRENCE WHOSE DATE PASSED WITH NOBODY PAYING IT (§3.2, `ClaimCalculator#overdue?`). **
#
# NO PAYMENT HISTORY ON THE POLICY ITEM, AND THAT IS THE WHOLE OF THE STATE. A cycle rolls when a
# bill is PAID and never when its date goes by, so with nothing ever spent on the Renters Policy
# item the occurrence stays anchored six days back: `#next_due_on` is a date in the past, which is
# `#overdue?` verbatim. §3.2's catch-up formula floors `periods_left` at 1 for a date already past,
# so the fund is WHOLE — which is the ordinary shape of an overdue bill rather than the exception,
# and it is what makes the trouble strip say "it's all there — pay it and the fund starts again"
# rather than "the fund is short". Both branches of that sentence exist; this demo plants the one
# a household that did everything right except write the cheque actually lands in.
#
# It also keeps the dead-rule detector honest: a single entry a year back would make detector 4 call
# an annual premium dead, which is a false sentence this demo should not plant on a money screen.
# ---------------------------------------------------------------------------------------------
renters_insurance = holder.call("Renters Insurance", 10, "#4DB6AC")
rule.call(
  category: renters_insurance,
  item: renters_insurance.items.create!(name: "Renters Policy"),
  amount: 180,
  interval_months: 12,
  anchor_date: today - 6,
  rule_type: :bill
)

# FOUR MORE COMMITMENTS, and the SHAPE OF EACH ONE IS CHOSEN SO THE DRIFT PANEL STAYS HONEST.
#
# A rate rule on a category with NO spending is exactly what the drift detector calls the starkest
# drift there is — "Holiday Gifts has averaged $0.00 for 4 periods, your rule says $200". One of
# those is a sentence worth planting (see Household Supplies above); four would be four suggestions
# telling the demo user to zero four rules they have not spent from YET, on a panel whose whole job
# is to be believed.
#
# So the two that are genuinely SAVED FOR are dated (a dated rule is not in drift's population at
# all), and the two that are genuinely SPENT every period carry the spending to match.
holiday_gifts = holder.call("Holiday Gifts", 11, "#F06292")
rule.call(
  category: holiday_gifts,
  amount: 1_200,
  interval_months: 12,
  anchor_date: today + 2.months,
  rule_type: :choice
)

quarterly_taxes = holder.call("Quarterly Taxes", 12, "#78909C")
rule.call(
  category: quarterly_taxes,
  amount: 1_800,
  interval_months: 3,
  anchor_date: today + 2.months,
  rule_type: :bill
)

# The two that ARE spent every period, at the rate their rules claim — so the drift panel has
# nothing to say about either, which is the half of the detector only a category it DECLINES to
# report can prove. Their money went out inside the four complete periods behind us, so this period
# they read $0.00 of their rate like every other untouched envelope.
medical_copays = holder.call("Medical Copays", 13, "#4FC3F7")
rule.call(category: medical_copays, amount: 60, basis: :per_period, rule_type: :usage)
copay_visits = medical_copays.items.create!(name: "Copays")

prescriptions = holder.call("Prescriptions", 14, "#4DD0E1")
rule.call(category: prescriptions, amount: 35, basis: :per_period, rule_type: :bill)
pharmacy = prescriptions.items.create!(name: "Pharmacy")

# ---------------------------------------------------------------------------------------------
# THE GOALS — §3.2's WALK, WITH A DAY AT THE END OF IT (two-shapes §2).
#
# ** A GOAL IS A DATED RULE WHOSE AMOUNT IS ITS TARGET (two-shapes §2 row 5, Henry's ruling of
# 2026-09-05: "build up is just a higher target on a timeline longer than a period"). ** It was a
# rule that CARRIED its unspent money over toward a separate figure, and a figure on the CATEGORY
# before that. `ClaimCalculator#shape` reads one column now — the anchor — so "$10,000 by next
# September" is the same shape as "$1,500 due on the 1st", and the only thing that makes it a goal
# is how far away the day is.
#
# ** EVERY GOAL HERE NAMES A DAY, AND THAT IS WHAT THE DEMO IS SHOWING. ** A fund with no deadline
# claimed only what its owner chose to put in it; a fund with one claims `remaining ÷ periods left`
# every period, whether or not anybody set money aside. That is the ruling's real consequence and it
# is visible in the header's figures: the household's rules ask a great deal more of a period than
# they did, and the trouble strip says so.
#
# Priorities 15 and up leave the household's bills ahead of them: a goal that gives way LAST, ahead
# of the rent, is not a budget anybody runs. ** THE TYPE DECIDES BEFORE THE PRIORITY DOES (§3), so
# the three types below are what really order these five: `choice` on the three the household could
# stop saving into, `usage` on the house deposit, `bill` on the emergency fund — which is the one
# fund this demo says must not be raided, and the give-way walk never reaches it.
# ---------------------------------------------------------------------------------------------
Rails.logger.debug "Creating the savings goals..."

emergency_fund = holder.call("Emergency Fund", 15, "#26A69A")
vacation = holder.call("Vacation to Europe", 16, "#FF8A65")
house_fund = holder.call("House Down Payment", 17, "#BA68C8")

# SPENDING OUT OF A GOAL — the one lane on the demo that reaches the entry form's goal arm, where
# the bar is drawn against the TARGET rather than against a per-period rate.
vacation_costs = vacation.items.create!(name: "Flights & Hotels")

# ** THE FIVE GOALS, EACH A ONE-OFF DATED RULE. ** The amount IS the target and the anchor is the day
# it has to be there; §3.2's catch-up then divides what is still missing by the periods left, every
# period, which is what a person means by "saving toward it".
#
# ** THERE ARE THREE GOALS WHERE THERE WERE FIVE, AND THE TWO THAT WENT ARE THE RULING'S COST SAID
# IN FIGURES. ** `New Car` ($15,000) and `Retirement Supplement` ($100,000) had no standing rate at
# all: they held whatever the household set aside and asked nothing of a period. A goal names a DAY
# now, so it asks `remaining ÷ periods left` EVERY period whether or not anybody adds to it — and
# measured on this demo those two alone asked **$677.57 a period** and had accrued **$11,010.95**
# between them six months in. A household bringing in $2,050 a period does not have a $100,000
# retirement goal and a $50,000 house deposit at once; keeping them would have made every screen in
# the demo a wall of red about a budget nobody could run, which teaches nothing about the app.
#
# WHAT IS LEFT IS THE THREE THE PLAN NAMES, with the dates it names them by: Vacation to Europe
# $5,000 by Jun 1 2027, Emergency Fund $10,000 by Sep 1 2027, House Down Payment $50,000 by Jan 1
# 2031. The demo is still structurally underwater — it always was, by $53 a period — and it is now
# underwater by an amount a person can see the cause of.
#
# ** THE TYPES ARE UNCHANGED, and they are what order these three in the give-way walk: `bill` on the
# emergency fund, `usage` on the house deposit, `choice` on the vacation — the one the household
# could stop saving into.
{
  vacation => { target: 5_000, due: Date.new(2027, 6, 1), type: :choice },
  emergency_fund => { target: 10_000, due: Date.new(2027, 9, 1), type: :bill },
  house_fund => { target: 50_000, due: Date.new(2031, 1, 1), type: :usage }
}.each do |goal, shape|
  rule.call(
    category: goal,
    amount: shape[:target],
    basis: :monthly,
    interval_months: nil,
    anchor_date: shape[:due],
    rule_type: shape[:type]
  )
end

# ---------------------------------------------------------------------------------------------
# ** THE RULE OUTSIDE THE GIVE-WAY ORDER — the Budget page's "Not in the give-way order" band. **
#
# A category with NO holding date carrying a rule. `Category.in_fill_order` is holders only, so this
# rule cannot be ranked and cannot be dragged — but `ClaimLedger` counts EVERY rule into `#free`, so
# its $25 is subtracted from the household's money every period while `CategoryLedger
# ::ENTRY_CATEGORY_ID` attributes nothing spent here against it. That is the exact asymmetry the
# band exists to name, and one field on the category form fixes it.
#
# NO SPENDING AT ALL, deliberately: the rate detector's population is the categories that hold
# nothing, and three periods of receipts here would make the panel propose a rule for a category
# that already has one.
# ---------------------------------------------------------------------------------------------
streaming = lane.call("Streaming", :expense, "#9CCC65")
rule.call(category: streaming, amount: 25, basis: :per_period, rule_type: :choice)

# ---------------------------------------------------------------------------------------------
# THE CATEGORIES THAT HOLD NOTHING — no `funded_since`, so their spending is attributed to no
# envelope and reads straight against `free`. This is what the app means by "it comes out of what's
# available", and it is the population the rate detector proposes rules for. Four flows, one entry a
# period, deliberately UNEVEN — amounts inside 25% of each other on a whole number of months apart
# are what the DATED BILL detector looks for, and a fortnightly flow that happened to land on even
# amounts would be proposed as a bill instead of as a rate.
# ---------------------------------------------------------------------------------------------
Rails.logger.debug "Creating the spending that comes out of what's free..."

transportation = lane.call("Transportation", :expense, "#64B5F6")
shopping = lane.call("Shopping", :expense, "#F06292")
personal_care = lane.call("Personal Care", :expense, "#FF8A65")
entertainment = lane.call("Entertainment", :expense, "#BA68C8")

fuel = transportation.items.create!(name: "Gas & Transit")
body_shop = transportation.items.create!(name: "Body Shop")
purchases = shopping.items.create!(name: "Household & Clothing")
haircuts = personal_care.items.create!(name: "Salon & Pharmacy")
outings = entertainment.items.create!(name: "Films & Nights Out")

# One entry per complete period, oldest first — periods 5 back through 1 back, which is five of
# the six the rate detector measures over. Three appearances are the minimum and one of them has
# to fall in the most recent three periods, so a flow this steady clears both gates with room.
buffer_flows = [
  [fuel, [205, 241, 186, 232, 198]],
  [purchases, [231, 298, 212, 264, 187]],
  [haircuts, [141, 127, 152, 96, 118]],
  [outings, [176, 219, 132, 248, 165]]
]

buffer_flows.each do |item, amounts|
  amounts.each_with_index do |amount, index|
    on = periods_ago[5 - index] + 2
    log.call(item, amount, on, "#{item.name} · #{on.strftime("%b %-d")}")
  end
end

# ONE occurrence, over $100, on an item with nothing else against it — and therefore NO dated-bill
# suggestion: one payment is not a schedule, so the detector stays silent below its two-occurrence
# floor (SuggestionEngine::BILL_MIN_OCCURRENCES). It is seeded to hold that silence honest.
log.call(body_shop, 530, periods_ago[3] + 6, "Rear bumper repair")

# A DAY-OF spend inside the CURRENT period, on a category no rule claims — the UNRULED row on Home's
# "This period" section: `spent $48.00`, no bar and no pressure, because there is nothing for a bar
# to be a fraction of.
log.call(fuel, 48, today, "Fill-up on payday")

# ---------------------------------------------------------------------------------------------
# THE HISTORY. Six complete periods of it, which is exactly the window the widest detector reads.
# Every entry is money the household actually spent, and the claims the screens report are computed
# over it — not an opening figure chosen to make a screen look right.
# ---------------------------------------------------------------------------------------------
Rails.logger.debug "Creating the paycheck and the history it paid for..."

paycheck = lane.call("Paycheck", :income, "#66BB6A")
direct_deposit = paycheck.items.create!(name: "Direct Deposit")

# $2,600 on every boundary from six periods back to today. The one today is this period's income;
# the six before it are what the pot carried in.
(0..6).each do |n|
  log.call(direct_deposit, 2_600, periods_ago[n], "Paycheck deposited to Checking")
end

# THE RENT, THREE MONTHS OF IT — and each payment is a FULFILMENT (§3.2), which is the only thing
# that drops the fund and rolls the cycle. Every one is before the rule's anchor, so the occurrence
# the household is saving for is still the one ten days out.
#
# THE SET-ASIDE THAT USED TO SIT BESIDE EACH PAYMENT IS GONE, and Rent is the clearest case of the
# header's ruling: the $1,500 was the distribution handing the envelope its money, which §3.2's
# catch-up formula now computes on its own. It could not have become an adjustment even if it should
# have — Rent's only rule names an item, and `DropTheDistribution#unfundable_ends` refuses exactly
# that shape.
(1..3).each do |n|
  on = today - n.months
  log.call(rent_item, 1_500, on, "Rent for #{on.strftime("%B")}")
end

# THE UTILITY BILLS, THE SAME THREE MONTHS. Four items in ONE category, which is the honest
# household shape: a rule may only name an item of the category it funds, so item-named categories
# would be mutually exclusive. Electric carries the rule; Phone, Internet and Water carry none, so
# each of them is a dated-bill suggestion offering to JOIN this category — the reuse branch, which
# proposals on unfunded categories can never reach.
utility_bills_by_item = [[electric_item, 120, 0], [phone_item, 85, 2], [internet_item, 65, 4], [water_item, 48, 6]]

(1..3).each do |n|
  utility_bills_by_item.each do |item, amount, offset|
    on = (today - n.months) + offset
    log.call(item, amount, on, "#{item.name} for #{on.strftime("%B")}")
  end
end

# THE GROCERIES, FOUR PERIODS OF IT — the drift window exactly. $460 spent every period against a
# $400 rule, so the observed rate is $60 over the rule and the panel says so. Two shops a period
# rather than one, because that is what a fortnight of groceries is. Nothing lands in the CURRENT
# period, which is why the row reads `$0.00 of $400.00` on the morning it opened.
(1..4).each do |n|
  opened_on = periods_ago[n]
  log.call(supermarket, 230, opened_on + 3, "Supermarket shop")
  log.call(supermarket, 230, opened_on + 9, "Supermarket shop")
end

# THE TRANSIT PASSES THAT STOPPED. Two periods of a fortnightly pass, six and five periods back,
# and nothing since — three complete empty periods is what detector 4 calls dead, and the rule is
# the only thing left of it.
[6, 5].each { |n| log.call(transit_pass, 60, periods_ago[n] + 2, "Fortnightly transit pass") }

# ** THE SET-ASIDES — the only purpose-side rows this demo writes (§3.3). ** Two goals, seven
# periods each, every one a positive adjustment on that goal's rule. They are money the household put
# in ON TOP of what the rule's own catch-up asks for: a goal accrues `remaining ÷ periods left` every
# period from `demo_start` whether or not anybody adds to it (two-shapes §2), so each of these four
# holds its accrual PLUS its set-asides rather than the set-asides alone. That is the change of shape
# said in figures, and the header's table carries what each one comes to.
#
# DATED ON THE BOUNDARIES, SIX PERIODS BACK THROUGH TODAY, and every one of them counts — which is
# the accrual-span ruling in the header doing its work. The rules are born on `demo_start`, so
# `ClaimCalculator#countable_span` opens six months back and each row lands in the period its date
# falls in. Dated inside the current period instead, all seven would sum onto one afternoon.
contributions = [[emergency_fund, 100], [house_fund, 150]]

(0..6).each do |n|
  contributions.each { |category, amount| set_aside.call(category, amount, periods_ago[n]) }
end

# A weekend of the trip already booked, out of the money the Vacation rule has been accruing — a
# FULFILMENT on a dateless target, which drops the built-up by what was spent and leaves the goal to
# go on accruing toward the same $5,000. Single-occurrence, so no dated bill comes of it.
log.call(vacation_costs, 180, periods_ago[3] + 5, "Flight deposit")

# THE TWO CATEGORIES THAT ARE SPENT AT EXACTLY THE RATE THEY CLAIM, over the four complete periods
# the drift detector measures: the rule is right, so the panel is silent about them.
(1..4).each do |n|
  log.call(copay_visits, 60, periods_ago[n] + 4, "Clinic copay")
  log.call(pharmacy, 35, periods_ago[n] + 6, "Pharmacy refill")
end

# ---------------------------------------------------------------------------------------------
# THIS PERIOD'S OWN SPENDING. Everything above is history; these three receipts are dated `today`,
# which is the only elapsed day of the current period, and they are the whole of what makes the
# "This period" rows read anything but $0.00.
# ---------------------------------------------------------------------------------------------

# THE OVERSPEND, on the fortnight's first evening: $110 against a $100 rule, so the claim clamps to
# zero and the $10 excess came out of what is free.
log.call(restaurants, 110, today, "Dinner out")

# The dinner in the period that closed yesterday — left where it is deliberately, so Dining Out has
# a receipt inside the four complete periods the drift detector measures and the panel says
# "averaged $17.50" rather than "averaged $0.00".
log.call(restaurants, 70, today - 2, "Dinner out")

# THE RATE ROW WITH ROOM LEFT: $45 of a $120 fortnight, so $75.00 is still claimable.
log.call(cleaning, 45, today, "Detergent, paper towels, bin bags")

# Pet Care's own lane, inside the four complete periods — kibble on the rate rule and nothing on the
# vet's, whose $180 bill is still twenty days out.
log.call(pet_food, 34, periods_ago[1] + 2, "Kibble and litter")

# ---------------------------------------------------------------------------------------------
# THE OTHER THREE ACCOUNTS — the physical ledger, and the only place the word "account" means
# anything now. Every one of these entries is INCOME that landed somewhere other than main, so the
# entry belongs to the pot and one routing movement says where the cash went.
# ---------------------------------------------------------------------------------------------
Rails.logger.debug "Creating the routed income and the overdrawn account..."

ally_transfers = lane.call("Ally Transfers", :income, "#42A5F5")
transfer_in = ally_transfers.items.create!(name: "Transfer In")
deposit.call(transfer_in, 400, periods_ago[4], "Moved to Ally Savings", ally)
deposit.call(transfer_in, 400, periods_ago[2], "Moved to Ally Savings", ally)
deposit.call(transfer_in, 1_000, today, "Moved to Ally Savings", ally)

# HEALTH SAVINGS — the two contributions that straddle the period boundary, which makes this the
# one account whose inflow is obviously split between "before this period" and "this period".
hsa_contributions = lane.call("Health Savings Contributions", :income, "#4DD0E1")
hsa_payroll = hsa_contributions.items.create!(name: "Payroll Contribution")
deposit.call(hsa_payroll, 200, today - 10, "Pre-tax HSA contribution", health_savings)
deposit.call(hsa_payroll, 200, today, "Pre-tax HSA contribution", health_savings)

# SIDE GIG CHECKING — THE ONLY ACCOUNT IN THE RED, and the shape the trouble strip's :overdraft arm
# has a line for. `AccountLedger#balance_of` is movements only for an account that is not the pot,
# so the way an account goes negative is a movement OUT of it that its inflows do not cover.
#
# The story is the household's freelance income: $1,300 of invoices routed into the side account,
# then $1,600 moved back to Checking to pay the quarterly estimated tax bill out of the pot,
# because that is where the cash actually leaves (§2). Ordinary, recoverable and entirely legible —
# an account that looks broken for no reason teaches the wrong lesson.
side_gig_income = lane.call("Side Gig Income", :income, "#26C6DA")
invoices = side_gig_income.items.create!(name: "Client Invoice")
deposit.call(invoices, 900, periods_ago[2], "Invoice #114 paid", side_gig)
deposit.call(invoices, 400, today, "Invoice #117 paid", side_gig)

# THE TAX BILL ITSELF — an expense out of what's free, on a category that holds nothing. Like the
# bumper repair above it is a single occurrence, so the dated-bill detector says nothing of it.
estimated_taxes = lane.call("Estimated Taxes", :expense, "#78909C")
log.call(estimated_taxes.items.create!(name: "Federal Estimate"), 1_600, today - 3, "Q3 estimated tax payment")
move.call(side_gig, checking, 1_600, today - 3)

Rails.logger.debug "Seed data created successfully!"
