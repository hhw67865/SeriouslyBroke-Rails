# frozen_string_literal: true

# THE DEMO, ENVELOPE-NATIVE.
#
# WHAT THIS FILE MAY WRITE, AND WHAT IT MAY NOT. Post-cutover shapes only: accounts, budget
# envelopes, savings goals, pool-mode funding rules, PoolMovements, income and expense entries, a
# declared period and a typical income. It writes NO category-mode budget (a cap —
# `budgets.category_id` is nil on every row here), NO savings category or savings entry, and NO
# category without a pool: every category names the lane its money moves through, income at an
# account and expense at its envelope, its goal or its account. `spec/seeds_spec.rb` greps this
# file for the legacy constructs AND asserts the database after a replant, so the two halves of
# that promise cannot drift apart.
#
# THE SCREEN STATES ARE THE DELIVERABLE, AND THE TABLE IS BELOW rather than in a scratch report
# that is not in the repository. Four accounts carry four distinct distribution screens — short
# with a partial waterfall and a cutoff, covered but opened by an alert, overdrawn with a negative
# available, and all-clear collapsed — and every envelope further down is annotated with the state
# it exists to put on a screen. Each state is carried by exactly ONE account, so a change to an
# account's balance or rules can retire a screen silently: read this table before editing an
# account, not after. `spec/seeds_spec.rb` plants these figures as literals, so a change to the
# demo has to argue with them rather than quietly restate them.
#
#   THE FOUR ACCOUNTS, THE SCREEN EACH ONE CARRIES, AND ITS HEADLINE FIGURES
#
#   CHECKING (the default account, target $2,000) — SHORT: the full waterfall, the cutoff line
#     drawn, both sweep clauses. `Distribute $560.00`; `Buffer carried over $408.00` · `Income this
#     period $2,600.00` · `Spent and moved this period -$2,573.00` · `Swept back from Household
#     Supplies and Pet Care $125.00` · `Available $560.00`; `$593.43 of what your envelopes asked
#     for isn't there`; 8 rows, with `— ran out here · $593.43 unfunded —` after row 3; and
#     `Stays in buffer · you wanted $2,000.00  $408.00 → $0.00`.
#
#   ALLY SAVINGS (target $5,000) — COVERED, EXPANDED BY THE ALERTS BAND ALONE, which is the only
#     screen where an alert is the sole cause of expansion. `Distribute $1,620.00`; `$620.00` /
#     `$1,000.00` / `$1,620.00`; the header `Every envelope gets what it asked for, but something
#     below still needs you`; one alert row (`Renters Insurance · overdue · was Aug 11 · Its money
#     is already there`); one waterfall row (`1 Holiday Gifts $200.00`); no cutoff.
#
#   SIDE GIG CHECKING (target $1,000) — OVERDRAWN, so Available is negative and there is nothing to
#     distribute. `Nothing to distribute`; `Side Gig Checking is $300.00 in the red, sweeps
#     included`; `Buffer carried over -$700.00` · `Income this period $400.00` · `Available
#     -$300.00`; the cutoff is drawn ABOVE row 1 (`1 Quarterly Taxes $0.00 of $200.00`).
#
#   HEALTH SAVINGS (target $1,500) — ALL CLEAR, COLLAPSED, plus the "Show every envelope" control.
#     `Distribute $400.00`; `$200.00` / `$200.00` / `$400.00`; `2 envelopes funded in full, $95.00
#     out — $305.00 stays in your buffer · you wanted $1,500.00.`; no table and no boxes until the
#     link is followed to `expand=1`, which is the only place the third header branch renders
#     (`Every envelope gets what it asked for. You asked to see the whole split, so here it is.`).
#
# NO `rand`, ANYWHERE. The previous seeds sprinkled `rand` through their entries and needed an
# `srand` to stay reproducible; every figure here is written down, so a replant lands on the same
# balances without a seeded PRNG to remember.
#
# EVERY DATE IS RELATIVE TO THE RUN DAY, AND THE STATES HOLD ON ANY RUN DAY. The period is
# declared biweekly and anchored on today, so today opens a period and `today - 14n` is the
# boundary n periods back. The suggestion engine measures in COMPLETE periods (the six ending
# yesterday), and the entries below are placed inside named periods rather than inside calendar
# months for exactly that reason. The bills that must look monthly — the rent, the four utility
# items — step by `n.months` from today instead, which is a whole number of months apart on every
# run day, and they are all dated at least 24 days back so no run day can slide one of them past
# the Utilities anchor and roll the overdue bill this demo needs.
#
# THE ZONE IS SET BEFORE THE FIRST RECORD IS SAVED, and it has to be.
#
# `entries.date` and `pool_movements.date` are DATETIME columns, so ActiveRecord casts the Date
# handed to `date:` through `Time.zone` — which in a rake process is the application default, UTC,
# because config/application.rb never sets one. Every date-bounded query in the app resolves in
# the REQUEST zone instead: ApplicationController wraps each request in
# `Time.use_zone(current_user.timezone)`, and `User#period_datetimes_containing` widens its range
# with `Date#beginning_of_day`, which reads that zone. Seeded without this line, the demo user's
# paycheck — dated `today`, the day the period opened — was stored as 00:00 UTC and read back as
# 20:00 the PREVIOUS evening in New York, four hours before its own period began, and the
# distribution screen reported `Income this period $0.00` beside it.
#
# A local rather than a constant: seeds.rb is `load`ed, and `bin/ci` runs it more than once in a
# session, so a constant here would warn about being reinitialised.
demo_timezone = "America/New_York"
Time.zone = demo_timezone

# DELETE IN FK ORDER, AND `Budget` COMES BEFORE `Item` — which is a correction, not a re-spelling
# of the order that was here.
#
# `budgets.item_id` is a non-cascading foreign key, so an item-backed funding rule pins its item:
# with `Item` ahead of `Budget` this loop raised `PG::ForeignKeyViolation ... on table "budgets"`
# and left the database holding pools, categories and items with no entries and no movements at
# all. It was latent rather than new — the previous seeds wrote item-backed rules too — and it was
# invisible because `db:seed:replant` TRUNCATES before it loads this file, so the loop only ever
# ran against an empty database. `bin/setup`'s plain `db:seed` does not truncate, and on any
# database that already holds a demo it is the path that breaks. Spec §7a's teardown rewrite,
# landing here because replant needed it.
#
# PoolMovement still leads: its keys to both pools and entries are non-cascading, so any movement
# on the table makes Entry.delete_all and Pool.delete_all violate them. `pools` references itself
# through `account_id`, and a single-statement `DELETE FROM pools` is fine — Postgres fires the NO
# ACTION triggers at the end of the statement, by which time no row is left to be pointed at.
# `users.default_account_id` nullifies on pool delete, so User can come last.
Rails.logger.debug "Clearing existing data..."
[PoolMovement, Entry, Budget, Item, Category, Pool, User].each do |model|
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
# (ApplicationController sets it), so Home computes against the New York date while a seed run
# late in the evening computes against the UTC one — a day apart. Seeded with the UTC date, the
# Dentist bill below anchored a day late and the period boundary landed INSIDE its window, so the
# pool that state exists to demonstrate rendered as something else entirely.
today = Time.find_zone!(user.timezone).today

# THE ANCHOR IS TODAY, so today is a period boundary and the current period is `today..today+13`.
# Two things follow, and both are load-bearing. The Dentist bill three days out is genuinely
# unreachable — no boundary falls between tomorrow and its due date — and every complete period
# the suggestion engine measures in is exactly `today - 14n .. today - 14(n-1) - 1`.
#
# `typical_income` is what the user SAYS they bring in, and it is $200 under the paycheck below on
# purpose: it is a declaration, not a measurement, and §9's structural check compares it against
# `Budget.steady_need` — $2,661.92 here — so the demo is structurally underwater and the sacrifice
# view has a screen.
user.update!(period_cadence: :biweekly, period_anchor_date: today, typical_income: 2_400)

# ---------------------------------------------------------------------------------------------
# Builders. Every record below goes through one of these, so a shape this demo may not write —
# a cap, a savings entry, a pool-less category — has nowhere to come from.
# ---------------------------------------------------------------------------------------------

# n periods back from today, on the boundary. The period that opened here closed on
# `periods_ago[n - 1] - 1`, which is the window the engine's detectors measure in.
periods_ago = ->(n) { today - (n * 14) }

account = lambda do |name, target|
  user.pools.create!(name: name, pool_type: :account, target_amount: target)
end

envelope = lambda do |name, home, priority|
  user.pools.create!(name: name, pool_type: :budget, account: home, priority: priority)
end

goal = lambda do |name, target, home, priority|
  user.pools.create!(name: name, pool_type: :savings, target_amount: target, account: home, priority: priority)
end

# A CATEGORY ALWAYS NAMES ITS POOL. There is no arity here that leaves `pool` nil, which is the
# one structural guarantee this file makes about categories.
lane = lambda do |name, type, pool, color|
  user.categories.create!(name: name, category_type: type, color: color, pool: pool)
end

log = ->(item, amount, on, description) { item.entries.create!(amount: amount, date: on, description: description) }

# MONEY THE USER MOVED BY HAND — `kind` stays at its default `transfer`, which is what every
# movement in this demo is. A distribution writes `allocation` and `sweep` rows and DELETES them
# on a re-run, so seeding the demo's history as distributed would hand the first confirm button
# a period whose funding it was entitled to replace.
move = ->(from, to, amount, on) { PoolMovement.create!(from_pool: from, to_pool: to, amount: amount, date: on) }

# ---------------------------------------------------------------------------------------------
# THE ACCOUNTS. Four, and each carries one distribution screen that no other can.
# ---------------------------------------------------------------------------------------------
Rails.logger.debug "Creating the four accounts..."

checking = account.call("Checking", 2_000)
ally = account.call("Ally Savings", 5_000)
side_gig = account.call("Side Gig Checking", 1_000)
health_savings = account.call("Health Savings", 1_500)

# THE ACCOUNT THE DEMO NOMINATES. `users.default_account_id` is read by the suggestion engine
# (every proposed envelope is offered inside it) and by the cutover migration's own idempotence
# check, and /distributions/new falls back to it when no pay has landed anywhere. Checking is
# where the pay lands and where the six row states live, so the demo says so rather than leaving
# it to `accounts.by_priority.first`, whose ties break on the NAME — which used to open the
# screen on Ally Savings.
user.update!(default_account: checking)

# ---------------------------------------------------------------------------------------------
# CHECKING — the short account. One envelope in each of the six row states from §4.4, two more
# whose rate period has already closed, and the goals the household saves into.
#
# The waterfall is PARTIAL here and the cutoff line is drawn, which is the branch this app exists
# for: $410.00 of available against $1,153.43 of asks. Every other account is covered, and a demo
# with no short account cannot show the standing band's stranded-cash clause either.
# ---------------------------------------------------------------------------------------------
Rails.logger.debug "Creating Checking's envelopes and their rules..."

rent = envelope.call("Rent", checking, 1)
utilities = envelope.call("Utilities", checking, 2)
dentist = envelope.call("Dentist", checking, 3)
car_insurance = envelope.call("Car Insurance", checking, 4)
dining = envelope.call("Dining Out", checking, 5)
groceries = envelope.call("Groceries", checking, 6)
supplies = envelope.call("Household Supplies", checking, 7)
pet_care = envelope.call("Pet Care", checking, 8)
commuter = envelope.call("Commuter Pass", checking, 9)

# The categories whose spending resolves INTO those envelopes. An envelope with no category
# behind it records no spending at all, which is the shape that made the drift detector read
# five envelopes as "you spend nothing, cut the rule to zero".
rent_bill = lane.call("Rent", :expense, rent, "#E57373")
utility_bills = lane.call("Utilities", :expense, utilities, "#FFD54F")
dining_out = lane.call("Dining Out", :expense, dining, "#81C784")
grocery_run = lane.call("Groceries", :expense, groceries, "#8BC34A")
supplies_run = lane.call("Household Supplies", :expense, supplies, "#90A4AE")
pet_supplies = lane.call("Pet Care", :expense, pet_care, "#A1887F")
commuting = lane.call("Commuter Pass", :expense, commuter, "#7986CB")

rent_item = rent_bill.items.create!(name: "Monthly Rent")
electric_item = utility_bills.items.create!(name: "Electric Bill")
phone_item = utility_bills.items.create!(name: "Phone")
internet_item = utility_bills.items.create!(name: "Internet")
water_item = utility_bills.items.create!(name: "Water")
restaurants = dining_out.items.create!(name: "Restaurants")
supermarket = grocery_run.items.create!(name: "Supermarket")
cleaning = supplies_run.items.create!(name: "Cleaning & Paper Goods")
pet_food = pet_supplies.items.create!(name: "Pet Food")
transit_pass = commuting.items.create!(name: "Transit Pass")

# ON TRACK — the rent, held in full, ten days before it is due. ITEM-BACKED, so the rule is
# genuinely payable and the bill's own history rolls its cycle; without an item the app assumes
# every bill was paid on time and no rule here could ever read `overdue`. The anchor is ten days
# out rather than on a calendar day, so the state does not depend on where in the month the seeds
# are run.
Budget.create!(pool: rent, item: rent_item, amount: 1_500, interval_months: 1, anchor_date: today + 10)

# OVERDUE — the date passed with no payment recorded against the item. The three earlier electric
# bills are all before this anchor, so `paid_since_anchor` is zero and the cycle has not rolled:
# a cycle rolls when a bill is PAID, never when its date goes by.
Budget.create!(pool: utilities, item: electric_item, amount: 120, interval_months: 1, anchor_date: today - 10)

# WON'T MAKE IT — $300 due in three days with no period boundary between tomorrow and then. No
# amount of future funding reaches it; only moving money already held can, which is what the fix
# button on Home offers.
Budget.create!(pool: dentist, amount: 300, anchor_date: today + 3)

# BEHIND — a six-monthly premium with nothing in it yet. Reachable, but the steady schedule says
# it should already hold part of the $1,200, and that lag is what the row names.
Budget.create!(pool: car_insurance, amount: 1_200, interval_months: 6, anchor_date: today + 3.months)

# OVERDRAWN — $100 in the envelope and $180 spent out of it. The debt belongs to the envelope,
# not to the account, which is why Checking stays healthy above it and why the entry form's
# impact card can show its overdraw arm on a category whose account is fine.
Budget.create!(pool: dining, amount: 150, basis: :per_period)

# LEFT TO SPEND — a rate envelope, topped back up every period, and the only state that shows a
# number you may actually spend. Its spending runs $460 a period against a $400 rule, which is
# the drift detector's one UPWARD suggestion: every other drift on this demo says cut.
Budget.create!(pool: groceries, amount: 400, basis: :per_period)

# The two whose rate period has ALREADY CLOSED. Funded one period back, so
# `PoolCalculator#period_closed?` — which measures from `last_funded_on`, not from today — is
# true for both, and three shipped features have a screen: the `Swept back from …` line in the
# sources breakdown, the ` · last period` suffix on a Home row, and the per-row `· $X swept back`
# clause on the waterfall.
#
# Household Supplies is the PLAIN case: one rate rule, nothing dated, so the whole $75 remainder
# sweeps. Pet Care is the MIXED case the partial sweep exists for — a live vet bill sharing the
# envelope with a rate rule, so `sweepable_amount` gives back the rate rule's $50 and leaves the
# vet's reserve where it is.
Budget.create!(pool: supplies, amount: 120, basis: :per_period)
Budget.create!(pool: pet_care, amount: 50, basis: :per_period)
Budget.create!(pool: pet_care, amount: 180, anchor_date: today + 20)

# A RULE STILL FUNDING SOMETHING THAT STOPPED — detector 4's only subject on this demo, and the
# one shape the other three cannot report. The household stopped buying the fortnightly transit
# pass five periods ago and the $60 rule is still reserving for it every period: item-backed (an
# item is what makes a rule payable and therefore what can stop) and per-period, so it never
# reads `overdue` and the sentence the panel prints is the whole of what is wrong with it.
Budget.create!(pool: commuter, item: transit_pass, amount: 60, basis: :per_period)

# ---------------------------------------------------------------------------------------------
# The goals the household saves into. Four sit in Checking; every one of them is HOUSED, which is
# the post-cutover shape — an account-less pool is exactly what the cutover's step 2 re-houses,
# so seeding one would make the migration's `up` a no-op no longer.
#
# Priorities 10 and up leave 1-9 to the envelopes. Priority is the order a distribution fills,
# and a savings goal funded ahead of the rent is not a budget anybody runs; a goal SHARING a
# number with an envelope in the same account would let `by_priority`'s name tie-break decide
# which of the two fills first.
# ---------------------------------------------------------------------------------------------
Rails.logger.debug "Creating the savings goals..."

emergency_fund = goal.call("Emergency Fund", 10_000, checking, 10)
vacation = goal.call("Vacation to Europe", 5_000, checking, 11)
house_fund = goal.call("House Down Payment", 50_000, checking, 12)
new_car = goal.call("New Car", 15_000, checking, 13)
retirement = goal.call("Retirement Supplement", 100_000, checking, 14)

# THE ONLY GOAL WITH A RULE, so it is the only one that ASKS. A dateless goal's ask is
# `min(its per-period rate, what is left to save)`, so a goal with no rule asks nothing and never
# reaches the waterfall — which is right, and which is why the other four are quiet rows.
Budget.create!(pool: retirement, amount: 150, basis: :per_period)

# SPENDING OUT OF A GOAL. `Pool::NOUNS` calls this one a "goal", and it is the only lane on the
# demo that reaches the entry form's goal arm — the bar there is drawn against the TARGET rather
# than against a per-period claim, which is a different arm of the same card. It is also the
# category page's goal-pointed arm.
vacation_spending = lane.call("Vacation Spending", :expense, vacation, "#26A69A")
vacation_costs = vacation_spending.items.create!(name: "Flights & Hotels")

# ---------------------------------------------------------------------------------------------
# THE BUFFER-FUNDED LANES — expense categories pointing straight at Checking. This is what the
# app means by "it comes out of your buffer": no envelope holds this money, so
# `Category#buffer_funded?` is true and the rate detector proposes one. Four categories, one
# entry a period, deliberately UNEVEN — amounts inside 25% of each other on a whole number of
# months apart are what the DATED BILL detector looks for, and a fortnightly flow that happened
# to land on even amounts would be proposed as a bill instead of as a rate.
# ---------------------------------------------------------------------------------------------
Rails.logger.debug "Creating the buffer-funded spending..."

transportation = lane.call("Transportation", :expense, checking, "#64B5F6")
shopping = lane.call("Shopping", :expense, checking, "#F06292")
personal_care = lane.call("Personal Care", :expense, checking, "#FF8A65")
entertainment = lane.call("Entertainment", :expense, checking, "#BA68C8")

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

# ONE occurrence, over $100, on an item with nothing else against it: the dated-bill detector's
# GUESSED arm, which proposes an annual interval and says in the sentence that it is a guess.
log.call(body_shop, 530, periods_ago[3] + 6, "Rear bumper repair")

# A DAY-OF spend inside the CURRENT period, so the sources breakdown's "Spent and moved this
# period" line has something of its own to report beside the funding movements.
log.call(fuel, 48, today, "Fill-up on payday")

# ---------------------------------------------------------------------------------------------
# THE HISTORY. Six complete periods of it, which is exactly the window the widest detector reads.
# Every movement out of Checking below is money the household actually moved, and every entry is
# money it actually spent — the balances the screens report are the arithmetic of this section,
# not an opening figure chosen to make a screen look right.
# ---------------------------------------------------------------------------------------------
Rails.logger.debug "Creating the paycheck and the history it paid for..."

paycheck = lane.call("Paycheck", :income, checking, "#66BB6A")
direct_deposit = paycheck.items.create!(name: "Direct Deposit")

# $2,600 on every boundary from six periods back to today. The one today is `Income this period`
# on the distribution screen; the six before it are what the buffer carried in.
(0..6).each do |n|
  on = periods_ago[n]
  log.call(direct_deposit, 2_600, on, "Paycheck deposited to Checking")
end

# THE RENT, THREE MONTHS OF IT. Funded and paid on the same day each month — the household moves
# the money across when the bill lands — so the envelope nets to zero over the history and holds
# exactly the $1,500 moved into it today. Every payment is before the rule's anchor, which is
# what keeps `paid_since_anchor` at zero and the next due date ten days out.
(1..3).each do |n|
  on = today - n.months
  move.call(checking, rent, 1_500, on)
  log.call(rent_item, 1_500, on, "Rent for #{on.strftime("%B")}")
end

# THE UTILITY BILLS, THE SAME THREE MONTHS. Four items in ONE envelope, which is the shape
# `SuggestionEngine#envelope_half` forces and the honest household one: a rule may only name an
# item in its own pool's categories, so item-named envelopes would be mutually exclusive.
# Electric carries the envelope's rule; Phone, Internet and Water carry none, so each of them is
# a dated-bill suggestion offering to JOIN this envelope — the reuse branch, which the
# account-pointed proposals below can never reach.
utility_bills_by_item = [[electric_item, 120, 0], [phone_item, 85, 2], [internet_item, 65, 4], [water_item, 48, 6]]

(1..3).each do |n|
  move.call(checking, utilities, 318, today - n.months)
  utility_bills_by_item.each do |item, amount, offset|
    on = (today - n.months) + offset
    log.call(item, amount, on, "#{item.name} for #{on.strftime("%B")}")
  end
end

# THE GROCERIES, FOUR PERIODS OF IT — the drift window exactly. $460 moved in and $460 spent
# every period against a $400 rule, so the observed rate is $60 over the rule and the panel says
# so. Two shops a period rather than one, because that is what a fortnight of groceries is.
(1..4).each do |n|
  opened_on = periods_ago[n]
  move.call(checking, groceries, 460, opened_on)
  log.call(supermarket, 230, opened_on + 3, "Supermarket shop")
  log.call(supermarket, 230, opened_on + 9, "Supermarket shop")
end

# THE TRANSIT PASSES THAT STOPPED. Two periods of a fortnightly pass, six and five periods back,
# and nothing since — three complete empty periods is what detector 4 calls dead, and the
# envelope nets to zero so the rule is the only thing left of it.
[6, 5].each do |n|
  move.call(checking, commuter, 60, periods_ago[n])
  log.call(transit_pass, 60, periods_ago[n] + 2, "Fortnightly transit pass")
end

# THE SAVINGS TRANSFERS — what a savings entry BECAME. The cutover re-recorded every one of them
# as a movement out of the buffer and into the goal, because that is what it always was: the
# user's own money crossing between their own pools, never money crossing the household's
# boundary. Written here in the shape the app now reads.
contributions = [[emergency_fund, 100], [vacation, 50], [house_fund, 150], [new_car, 75], [retirement, 150]]

(0..6).each do |n|
  contributions.each { |pool, amount| move.call(checking, pool, amount, periods_ago[n]) }
end

# A weekend of the trip already booked, out of the money set aside for it.
log.call(vacation_costs, 180, periods_ago[3] + 5, "Flight deposit")

# ---------------------------------------------------------------------------------------------
# THIS PERIOD'S OWN MOVES. Everything above is history; these three are what the household did
# with today's pay, and they are what leaves Checking short.
#
# `on: today` matters for all three: `PoolCalculator#period_closed?` measures from
# `last_funded_on`, so an envelope funded today is current by definition and nothing sweeps out
# from under the states these exist to show.
# ---------------------------------------------------------------------------------------------
move.call(checking, rent, 1_500, today)
move.call(checking, groceries, 400, today)
move.call(checking, dining, 100, today)

# The overspend that puts Dining Out in the red — $180 out of an envelope holding $100, both
# entries in the period that closed yesterday.
log.call(restaurants, 110, today - 6, "Dinner out")
log.call(restaurants, 70, today - 2, "Dinner out")

# The two closed envelopes' own spending, inside the period they were funded in.
move.call(checking, supplies, 120, periods_ago[1])
log.call(cleaning, 45, periods_ago[1] + 4, "Detergent, paper towels, bin bags")
move.call(checking, pet_care, 150, periods_ago[1])
log.call(pet_food, 34, periods_ago[1] + 2, "Kibble and litter")

# ---------------------------------------------------------------------------------------------
# ALLY SAVINGS — covered, and expanded by the ALERTS BAND alone.
#
# The band exists for one shape: a red pool that is ASKING FOR NOTHING. The annual premium was
# set aside a fortnight ago, on time; the policy renewed six days ago and the payment has simply
# not been made yet. So the envelope holds the whole $180, `BudgetCalculator#shortfall` is zero,
# the rule asks for nothing and `AllocationCalculator#fill` rejects the row — while `PoolStatus`
# still reads `overdue`, because a cycle rolls when a bill is PAID.
#
# HERE, AND NOT IN CHECKING, which is the whole point. Checking is short, so its screen is
# expanded already and this pool would ride along as decoration. Ally is COVERED: without the
# band its screen collapses to a headline, one summary line and a confirm button over the top of
# a bill that is already late. It is also the only place the covered-but-expanded copy — "Every
# envelope gets what it asked for, but something below still needs you" — reaches a real screen.
#
# Deliberately NOT folded into Checking's Utilities envelope. That one is the `overdue` ROW —
# late and UNFUNDED, so it still asks — and the distinction this band draws is exactly between a
# red pool with a row and a red pool without one. One envelope cannot be both.
#
# NO PAYMENT HISTORY ON THE POLICY ITEM, deliberately: a single entry a year back would make the
# dead-rule detector call an annual premium dead, which is a false sentence this demo should not
# plant on a money screen.
# ---------------------------------------------------------------------------------------------
Rails.logger.debug "Creating Ally Savings, its overdue-but-funded premium and its rate envelope..."

ally_transfers = lane.call("Ally Transfers", :income, ally, "#42A5F5")
transfer_in = ally_transfers.items.create!(name: "Transfer In")
log.call(transfer_in, 400, periods_ago[4], "Moved to Ally Savings")
log.call(transfer_in, 400, periods_ago[2], "Moved to Ally Savings")
log.call(transfer_in, 1_000, today, "Moved to Ally Savings")

renters_insurance = envelope.call("Renters Insurance", ally, 8)
insurance_bills = lane.call("Insurance Bills", :expense, renters_insurance, "#4DB6AC")
Budget.create!(
  pool: renters_insurance,
  item: insurance_bills.items.create!(name: "Renters Policy"),
  amount: 180,
  interval_months: 12,
  anchor_date: today - 6
)
# Out of Ally, not Checking — this envelope lives in the other account, and a movement between
# accounts is a bank transfer the spec puts out of scope. A fortnight ago, because "funded on
# time" means the money was there before the renewal date.
move.call(ally, renters_insurance, 180, periods_ago[1])

# A RATE rule rather than a dated one on purpose: a dated bill with nothing in it reads `behind`,
# which Car Insurance already demonstrates. Left unfunded so it still ASKS — a satisfied envelope
# is rejected from the waterfall and would take Ally's whole table off the screen with it.
holiday_gifts = envelope.call("Holiday Gifts", ally, 9)
Budget.create!(pool: holiday_gifts, amount: 200, basis: :per_period)

# ---------------------------------------------------------------------------------------------
# SIDE GIG CHECKING — the only account in the RED.
#
# `AllocationCalculator#available` is deliberately not clamped at zero, and both screens that read
# it branch on the negative: the distribution screen swaps its headline for "Nothing to
# distribute" and prints the buffer in `text-status-danger`, and Home's standing band adds a line
# for every one of `#overdrawn_accounts`.
#
# IT HAS TO BE A THIRD ACCOUNT rather than a state applied to one of the two above, and the
# arithmetic forces that: `available = balance + sweeps` and `#fill` clamps every row against it,
# so an account with a negative available funds NOTHING. Making Checking negative would delete the
# partial waterfall and its cutoff; making Ally negative would take its pot to zero in Home's
# `#account_pots` and silence the stranded-cash clause that account exists for.
#
# The story is the household's freelance income: the quarterly estimated tax payment left the
# account before the last invoice was paid. Ordinary, recoverable and entirely legible — an
# account that looks broken for no reason teaches the wrong lesson. It is also the demo's second
# GUESSED dated bill, and the only one whose category points at an ACCOUNT, so accepting it
# creates a new envelope rather than joining one.
# ---------------------------------------------------------------------------------------------
Rails.logger.debug "Creating the overdrawn third account..."

side_gig_income = lane.call("Side Gig Income", :income, side_gig, "#26C6DA")
invoices = side_gig_income.items.create!(name: "Client Invoice")
log.call(invoices, 900, periods_ago[2], "Invoice #114 paid")
log.call(invoices, 400, today, "Invoice #117 paid")

estimated_taxes = lane.call("Estimated Taxes", :expense, side_gig, "#78909C")
log.call(estimated_taxes.items.create!(name: "Federal Estimate"), 1_600, today - 3, "Q3 estimated tax payment")

# Left unfunded, so it still asks: a negative Available with no row under it would state the
# overdraft without showing what it costs.
quarterly_taxes = envelope.call("Quarterly Taxes", side_gig, 9)
Budget.create!(pool: quarterly_taxes, amount: 200, basis: :per_period)

# ---------------------------------------------------------------------------------------------
# HEALTH SAVINGS — the only CALM one, and the only collapsed distribution screen.
#
# Covered with nothing red, so `DistributionPresenter#expanded?` is false and /distributions/new
# renders the collapsed density: a headline, the sources breakdown, one summary line and the
# "Show every envelope" link, with no table and no boxes. Ally cannot also carry this — the
# alerts band needs a covered account WITH a red pool and the collapsed density needs a covered
# account with NONE — so they get one each.
#
# Every number here is chosen to keep it that way: two RATE rules and nothing dated, so no pool
# can ever read `overdue` or `won't make it` and no alert can appear; both envelopes empty, so
# they ASK; $400 against $95 of rules, so it is comfortably covered rather than covered by a
# margin the next edit could close by accident; never funded, so `#period_closed?` is false for
# want of a `last_funded_on` and nothing sweeps.
#
# The two contributions are the only ones in this demo that straddle the period boundary, which
# makes this the one screen where `Buffer carried over` and `Income this period` are both
# positive and obviously different money.
# ---------------------------------------------------------------------------------------------
Rails.logger.debug "Creating the fourth account, the calm one..."

hsa_contributions = lane.call("Health Savings Contributions", :income, health_savings, "#4DD0E1")
hsa_payroll = hsa_contributions.items.create!(name: "Payroll Contribution")
log.call(hsa_payroll, 200, today - 10, "Pre-tax HSA contribution")
log.call(hsa_payroll, 200, today, "Pre-tax HSA contribution")

# Two rather than one, so the collapsed summary reads "2 envelopes funded in full" and pluralize
# is exercised on a real screen. Distinct priorities because these two share an ACCOUNT: a tie
# here would be a real one, decided by `by_priority`'s name tie-break.
[["Medical Copays", 8, 60], ["Prescriptions", 9, 35]].each do |name, priority, amount|
  Budget.create!(pool: envelope.call(name, health_savings, priority), amount: amount, basis: :per_period)
end

Rails.logger.debug "Seed data created successfully!"
