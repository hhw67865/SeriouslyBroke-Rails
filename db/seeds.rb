# frozen_string_literal: true

# THE DEMO, CATEGORY-NATIVE (two-ledger spec §2/§5).
#
# WHAT THIS FILE MAY WRITE, AND WHAT IT MAY NOT. Post-drop shapes only: bank ACCOUNTS, expense and
# income CATEGORIES, funding rules on categories, ALLOCATIONS (the purpose ledger), ACCOUNT
# MOVEMENTS (the physical one), income routing, entries, a declared period and a typical income.
# There is no envelope, no goal pool, no `categories.pool_id` and no paid-from override, because
# none of those columns exists any more. `spec/seeds_spec.rb` greps this file for the legacy
# constructs AND asserts the database after a replant, so the two halves of that promise cannot
# drift apart.
#
# THE TWO LEDGERS, AND WHERE EACH ONE IS WRITTEN HERE.
#
#   PHYSICAL — where the money sits. `pot (= Checking) + Σ accounts`. Income and expense ENTRIES
#     all belong to the pot; the other three accounts are fed by movements alone, which is what
#     `Entry#route_income_to!` writes when income lands somewhere other than main.
#   PURPOSE — what the money is FOR. `available + Σ category holdings`. Every `allocate` below is
#     one row of it: money leaving the root and taking on a job.
#
# Both partitions equal bank truth — income minus expenses — and `spec/seeds_spec.rb` asserts that
# on the replanted demo, in raw SQL, against $7,461.00.
#
# THE SCREEN STATES ARE THE DELIVERABLE, AND THE TABLE IS BELOW rather than in a scratch report
# that is not in the repository.
#
#   ONE DISTRIBUTE SCREEN, NOT FOUR. The pool era gave each of four ACCOUNTS its own waterfall and
#   this table listed one screen per account. `AllocationCalculator` walks `Category.in_fill_order`
#   over ONE root now (§2), so there is one screen and it has to carry every state at once: SHORT,
#   with the cutoff line drawn, an ALERTS band above it, and both sweep clauses in the sources
#   breakdown.
#
#     available at the root   $1,775.00   income − unfunded spending − Σ allocations
#     + swept back              $125.00   Household Supplies $75.00, Pet Care $50.00
#     = the screen's figure   $1,900.00   against more than that in asks, so the cutoff is drawn
#     12 waterfall rows, 1 alert (Renters Insurance — overdue and already funded, so it asks for
#     nothing at all, which is the one shape the alerts band exists for)
#
#   THE SIX ROW STATES (§4.4), one category each, all on that one screen:
#     on track          Rent                — $1,500 held, the bill ten days out
#     overdue           Utilities           — the electric bill's date passed with nothing paid
#     won't make it     Dentist             — $300 due in three days, no boundary in between
#     behind            Car Insurance       — a $1,200 premium a month out with nothing in it yet
#     overdrawn         Dining Out          — holds -$80.00: $100 allocated, $180 of dinners
#     left to spend     Groceries           — $400 held against a $400-a-period rule
#
#   THE FOUR SUGGESTION DETECTORS, and the categories that feed each:
#     dated_bill (6)  the utility items carrying no rule of their own (Phone, Internet, Water),
#                     each offering to JOIN the Utilities category — the reuse branch — plus the
#                     one-off spends the engine reads as annual bills, the Body Shop repair and the
#                     quarterly tax estimate among them
#     rate (4)        Transportation, Shopping, Personal Care, Entertainment — the categories that
#                     hold nothing, so their spending reads straight against available
#     drift (4)       Groceries (the one UPWARD suggestion, $460 spent against a $400 rule),
#                     Dining Out, Household Supplies, Pet Care — every other drift says cut
#     dead_rule (1)   Commuter Pass — the fortnightly pass stopped five periods ago
#
#   THE THREE ACCOUNTS THAT ARE NOT THE POT, and what each one is for on Home:
#     Ally Savings        +$1,800.00  three routed transfers — the ordinary second account
#     Health Savings        +$400.00  two payroll contributions straddling the period boundary
#     Side Gig Checking     -$300.00  OVERDRAWN, which Home's standing band has a line for:
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
# are all dated at least 24 days back so no run day can slide one of them past the Utilities anchor
# and roll the overdue bill this demo needs.
#
# THE ZONE IS SET BEFORE THE FIRST RECORD IS SAVED, and it has to be.
#
# `entries.date`, `allocations.date` and `account_movements.date` are DATETIME columns, so
# ActiveRecord casts the Date handed to `date:` through `Time.zone` — which in a rake process is the
# application default, UTC, because config/application.rb never sets one. Every date-bounded query
# in the app resolves in the REQUEST zone instead: ApplicationController wraps each request in
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

# DELETE IN FOREIGN-KEY ORDER, AND THE TWO LEDGERS COME FIRST. `allocations` has non-cascading keys
# to `categories` and to `entries`, and `account_movements` has them to `pools` and to `entries`, so
# either table left standing makes `Entry.delete_all` and `Category.delete_all` violate them.
#
# `Budget` COMES BEFORE `Item`: `budgets.item_id` is a non-cascading foreign key, so an item-backed
# funding rule pins its item — with `Item` ahead of `Budget` this loop raised
# `PG::ForeignKeyViolation ... on table "budgets"`. It is invisible under `db:seed:replant`, which
# TRUNCATES first; `bin/setup`'s plain `db:seed` is the path that breaks.
#
# `users.default_account_id` nullifies on pool delete, so User can come last.
Rails.logger.debug "Clearing existing data..."
[AccountMovement, Allocation, Entry, Budget, Item, Category, Pool, User].each do |model|
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
# category that state exists to demonstrate rendered as something else entirely.
today = Time.find_zone!(user.timezone).today

# THE ANCHOR IS TODAY, so today is a period boundary and the current period is `today..today+13`.
# Two things follow, and both are load-bearing. The Dentist bill three days out is genuinely
# unreachable — no boundary falls between tomorrow and its due date — and every complete period
# the suggestion engine measures in is exactly `today - 14n .. today - 14(n-1) - 1`.
#
# `typical_income` is what the user SAYS they bring in, and it is $200 under the paycheck below on
# purpose: it is a declaration, not a measurement, and §9's structural check compares it against
# `Budget.steady_need` — $2,484.99 here — so the demo is structurally underwater and the sacrifice
# view has a screen.
user.update!(period_cadence: :biweekly, period_anchor_date: today, typical_income: 2_400)

# ---------------------------------------------------------------------------------------------
# Builders. Every record below goes through one of these, so a shape this demo may not write has
# nowhere to come from.
# ---------------------------------------------------------------------------------------------

# n periods back from today, on the boundary. The period that opened here closed on
# `periods_ago[n - 1] - 1`, which is the window the engine's detectors measure in.
periods_ago = ->(n) { today - (n * 14) }

account = ->(name) { user.pools.create!(name: name, pool_type: :account) }

# EVERY HOLDER STARTED HOLDING BEFORE THE HISTORY BELOW, and that is the funding-start rule
# (two-ledger spec §4) rather than decoration. A category counts its own spending only from
# `funded_since` on; earlier spending drains AVAILABLE. A demo whose categories all started today
# would push its entire seeded history onto the root and open every holder empty. Six months clears
# the deepest thing this file writes (three calendar months of rent, seven biweekly periods of
# paychecks), so every entry below lands where the sentence around it says it does.
demo_start = today - 6.months

# A CATEGORY THAT HOLDS MONEY — `Category#holder?` is `expense? && funded_since.present?`, and this
# is the only builder that stamps the column. `priority` is the fill order, over the user's WHOLE
# holder set now that there is one root to fill from.
holder = lambda do |name, priority, color, target: nil|
  user.categories.create!(
    name: name,
    category_type: :expense,
    color: color,
    funded_since: demo_start,
    priority: priority,
    target_amount: target
  )
end

# A CATEGORY THAT HOLDS NOTHING: no `funded_since`, so its spending reads against available and it
# is outside the waterfall entirely. This is what the app means by "it comes out of what's
# available", and it is the population the rate detector proposes rules for.
lane = lambda do |name, type, color|
  user.categories.create!(name: name, category_type: type, color: color)
end

log = lambda do |item, amount, on, description|
  item.entries.create!(amount: amount, date: on, description: description)
end

# INCOME THAT LANDED SOMEWHERE OTHER THAN MAIN. The entry itself always belongs to the pot — income
# lands in available and is allocated out of it — and this writes the ONE mirroring transfer that
# says the cash physically went elsewhere, exactly as the entry form does.
deposit = lambda do |item, amount, on, description, into|
  log.call(item, amount, on, description).tap { |entry| entry.route_income_to!(into) }
end

# MONEY LEAVING THE ROOT AND TAKING ON A JOB — one row of the purpose ledger. `from_category` is
# NULL, which IS available.
#
# `kind` STAYS AT ITS DEFAULT `transfer`, which is what every allocation in this demo is. A
# distribution writes `allocation` and `sweep` rows and DELETES them on a re-run, so seeding the
# demo's history as distributed would hand the first confirm button a period whose funding it was
# entitled to replace.
allocate = lambda do |category, amount, on|
  Allocation.create!(from_category: nil, to_category: category, amount: amount, date: on)
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
# THE SIX ROW STATES, one category each. Priorities 1-9 are the household's bills and running
# costs, in the order a distribution fills them.
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
transit_pass = commuter.items.create!(name: "Transit Pass")

# ON TRACK — the rent, held in full, ten days before it is due. ITEM-BACKED, so the rule is
# genuinely payable and the bill's own history rolls its cycle; without an item the app assumes
# every bill was paid on time and no rule here could ever read `overdue`. The anchor is ten days
# out rather than on a calendar day, so the state does not depend on where in the month the seeds
# are run.
Budget.create!(category: rent, item: rent_item, amount: 1_500, interval_months: 1, anchor_date: today + 10)

# OVERDUE — the date passed with no payment recorded against the item. The three earlier electric
# bills are all before this anchor, so `paid_since_anchor` is zero and the cycle has not rolled:
# a cycle rolls when a bill is PAID, never when its date goes by.
Budget.create!(category: utilities, item: electric_item, amount: 120, interval_months: 1, anchor_date: today - 10)

# WON'T MAKE IT — $300 due in three days with no period boundary between tomorrow and then. No
# amount of future funding reaches it; only moving money already held can, which is what the fix
# button on Home offers.
Budget.create!(category: dentist, amount: 300, anchor_date: today + 3)

# BEHIND — a six-monthly premium with nothing in it yet, one month out. Reachable, but the steady
# schedule says it should already hold most of the $1,200, and that lag is what the row names.
#
# ONE MONTH RATHER THAN THREE, AND THE DATE IS WHAT MAKES THE DEMO SHORT. `BudgetCalculator
# #required` spreads the shortfall over the boundaries left before the due date, so at three months
# out this premium asked about $92 a period and the household covered every rule it had — a demo
# with no shortfall cannot draw the cutoff line, which is the branch this app exists for. At one
# month it asks ~$600, the asks pass what is available, and the waterfall runs out partway down.
Budget.create!(category: car_insurance, amount: 1_200, interval_months: 6, anchor_date: today + 1.month)

# OVERDRAWN — $100 allocated and $180 spent out of it. The debt belongs to the CATEGORY, not to the
# bank account, which is the whole shape the two-ledger model exists to express: Checking is fine
# and Dining Out is not.
Budget.create!(category: dining, amount: 150, basis: :per_period)

# LEFT TO SPEND — a rate category, topped back up every period, and the only state that shows a
# number you may actually spend. Its spending runs $460 a period against a $400 rule, which is the
# drift detector's one UPWARD suggestion: every other drift on this demo says cut.
Budget.create!(category: groceries, amount: 400, basis: :per_period)

# The two whose rate period has ALREADY CLOSED. Funded one period back, so
# `HoldingCalculator#period_closed?` — which measures from `last_funded_on`, not from today — is
# true for both, and three shipped features have a screen: the `Swept back from …` line in the
# sources breakdown, the ` · last period` suffix on a Home row, and the per-row `· $X swept back`
# clause on the waterfall.
#
# Household Supplies is the PLAIN case: one rate rule, nothing dated, so the whole $75 remainder
# sweeps. Pet Care is the MIXED case the partial sweep exists for — a live vet bill sharing the
# category with a rate rule, so `sweepable_amount` gives back the rate rule's $50 and leaves the
# vet's reserve where it is.
Budget.create!(category: supplies, amount: 120, basis: :per_period)
Budget.create!(category: pet_care, amount: 50, basis: :per_period)
Budget.create!(category: pet_care, amount: 180, anchor_date: today + 20)

# A RULE STILL FUNDING SOMETHING THAT STOPPED — detector 4's only subject on this demo, and the
# one shape the other three cannot report. The household stopped buying the fortnightly transit
# pass five periods ago and the $60 rule is still reserving for it every period: item-backed (an
# item is what makes a rule payable and therefore what can stop) and per-period, so it never
# reads `overdue` and the sentence the panel prints is the whole of what is wrong with it.
Budget.create!(category: commuter, item: transit_pass, amount: 60, basis: :per_period)

# ---------------------------------------------------------------------------------------------
# THE ALERTS BAND'S ONE SUBJECT, and the reason it needs a category of its own.
#
# The band exists for one shape: a RED category that is ASKING FOR NOTHING. The annual premium was
# set aside a fortnight ago, on time; the policy renewed six days ago and the payment has simply
# not been made yet. So the category holds the whole $180, `BudgetCalculator#shortfall` is zero, the
# rule asks for nothing and `AllocationCalculator#fill` rejects the row — while `HoldingStatus`
# still reads `overdue`, because a cycle rolls when a bill is PAID.
#
# Deliberately NOT folded into Utilities. That one is the `overdue` ROW — late and UNFUNDED, so it
# still asks — and the distinction this band draws is exactly between a red category with a row and
# a red category without one. One category cannot be both.
#
# NO PAYMENT HISTORY ON THE POLICY ITEM, deliberately: a single entry a year back would make the
# dead-rule detector call an annual premium dead, which is a false sentence this demo should not
# plant on a money screen.
# ---------------------------------------------------------------------------------------------
renters_insurance = holder.call("Renters Insurance", 10, "#4DB6AC")
Budget.create!(
  category: renters_insurance,
  item: renters_insurance.items.create!(name: "Renters Policy"),
  amount: 180,
  interval_months: 12,
  anchor_date: today - 6
)

# FOUR MORE COMMITMENTS, and the SHAPE OF EACH ONE IS CHOSEN SO THE DRIFT PANEL STAYS HONEST.
#
# In the pool era these four sat in three different accounts and carried a per-period rate rule
# each, because every account needed a waterfall of its own to render. There is one waterfall now,
# and a rate rule on a category with NO spending is exactly what the drift detector calls the
# starkest drift there is — "Holiday Gifts has averaged $0.00 for 4 periods, your rule says $200".
# Four of those would be four suggestions telling the demo user to zero four rules they have not
# spent from YET, on a panel whose whole job is to be believed.
#
# So the two that are genuinely SAVED FOR are dated (a dated rule is not in drift's population at
# all), and the two that are genuinely SPENT every period carry the spending to match. What is left
# drifting is the four categories whose spending really has drifted, which is what the panel is for.
holiday_gifts = holder.call("Holiday Gifts", 11, "#F06292")
Budget.create!(category: holiday_gifts, amount: 1_200, interval_months: 12, anchor_date: today + 2.months)

quarterly_taxes = holder.call("Quarterly Taxes", 12, "#78909C")
Budget.create!(category: quarterly_taxes, amount: 1_800, interval_months: 3, anchor_date: today + 2.months)

# The two that ARE spent every period, at the rate their rules claim — so they read as ordinary
# funded categories and the drift panel has nothing to say about either.
medical_copays = holder.call("Medical Copays", 13, "#4FC3F7")
Budget.create!(category: medical_copays, amount: 60, basis: :per_period)
copay_visits = medical_copays.items.create!(name: "Copays")

prescriptions = holder.call("Prescriptions", 14, "#4DD0E1")
Budget.create!(category: prescriptions, amount: 35, basis: :per_period)
pharmacy = prescriptions.items.create!(name: "Pharmacy")

# ---------------------------------------------------------------------------------------------
# THE GOALS. A savings category is a holder with a TARGET (spec §3) — no separate pool, no separate
# type, and money never sweeps out of one because a target switches use-it-or-lose-it off.
#
# Priorities 15 and up leave the household's bills ahead of them: a goal funded before the rent is
# not a budget anybody runs.
# ---------------------------------------------------------------------------------------------
Rails.logger.debug "Creating the savings goals..."

emergency_fund = holder.call("Emergency Fund", 15, "#26A69A", target: 10_000)
vacation = holder.call("Vacation to Europe", 16, "#FF8A65", target: 5_000)
house_fund = holder.call("House Down Payment", 17, "#BA68C8", target: 50_000)
new_car = holder.call("New Car", 18, "#64B5F6", target: 15_000)
retirement = holder.call("Retirement Supplement", 19, "#AED581", target: 100_000)

# SPENDING OUT OF A GOAL — the one lane on the demo that reaches the entry form's goal arm, where
# the bar is drawn against the TARGET rather than against a per-period claim.
vacation_costs = vacation.items.create!(name: "Flights & Hotels")

# THE ONLY GOAL WITH A RULE, so it is the only one that ASKS. A dateless goal's ask is
# `min(its per-period rate, what is left to save)`, so a goal with no rule asks nothing and never
# reaches the waterfall — which is right, and which is why the other four are quiet rows.
#
# IT IS THE VACATION AND NOT THE RETIREMENT GOAL, and the reason is the drift panel. A rate rule on
# a category with no spending at all is drift's starkest sentence, and "Retirement Supplement has
# averaged $0.00 for 4 periods, your rule says $150" is a sentence that is TRUE of a retirement
# goal by definition and useless on a money screen. Vacation to Europe is the one goal the
# household actually draws on — a $180 flight deposit inside the drift window, against a $50 rule —
# so the rule and the spending agree and the panel says nothing about it.
Budget.create!(category: vacation, amount: 50, basis: :per_period)

# ---------------------------------------------------------------------------------------------
# THE CATEGORIES THAT HOLD NOTHING — no `funded_since`, so their spending reads straight against
# available. This is what the app means by "it comes out of what's available", and it is the
# population the rate detector proposes rules for. Four flows, one entry a period, deliberately
# UNEVEN — amounts inside 25% of each other on a whole number of months apart are what the DATED
# BILL detector looks for, and a fortnightly flow that happened to land on even amounts would be
# proposed as a bill instead of as a rate.
# ---------------------------------------------------------------------------------------------
Rails.logger.debug "Creating the spending that comes out of what's available..."

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

# ONE occurrence, over $100, on an item with nothing else against it: the dated-bill detector's
# GUESSED arm, which proposes an annual interval and says in the sentence that it is a guess.
log.call(body_shop, 530, periods_ago[3] + 6, "Rear bumper repair")

# A DAY-OF spend inside the CURRENT period, so the sources breakdown's "Spent and moved this
# period" line has something of its own to report beside the allocations.
log.call(fuel, 48, today, "Fill-up on payday")

# ---------------------------------------------------------------------------------------------
# THE HISTORY. Six complete periods of it, which is exactly the window the widest detector reads.
# Every allocation below is money the household set aside, and every entry is money it actually
# spent — the balances the screens report are the arithmetic of this section, not an opening
# figure chosen to make a screen look right.
# ---------------------------------------------------------------------------------------------
Rails.logger.debug "Creating the paycheck and the history it paid for..."

paycheck = lane.call("Paycheck", :income, "#66BB6A")
direct_deposit = paycheck.items.create!(name: "Direct Deposit")

# $2,600 on every boundary from six periods back to today. The one today is `Income this period`
# on the distribution screen; the six before it are what available carried in.
(0..6).each do |n|
  log.call(direct_deposit, 2_600, periods_ago[n], "Paycheck deposited to Checking")
end

# THE RENT, THREE MONTHS OF IT. Set aside and paid on the same day each month — the household
# assigns the money when the bill lands — so the category nets to zero over the history and holds
# exactly the $1,500 allocated to it today. Every payment is before the rule's anchor, which is
# what keeps `paid_since_anchor` at zero and the next due date ten days out.
(1..3).each do |n|
  on = today - n.months
  allocate.call(rent, 1_500, on)
  log.call(rent_item, 1_500, on, "Rent for #{on.strftime("%B")}")
end

# THE UTILITY BILLS, THE SAME THREE MONTHS. Four items in ONE category, which is the honest
# household shape: a rule may only name an item of the category it funds, so item-named categories
# would be mutually exclusive. Electric carries the rule; Phone, Internet and Water carry none, so
# each of them is a dated-bill suggestion offering to JOIN this category — the reuse branch, which
# the proposals on unfunded categories can never reach.
utility_bills_by_item = [[electric_item, 120, 0], [phone_item, 85, 2], [internet_item, 65, 4], [water_item, 48, 6]]

(1..3).each do |n|
  allocate.call(utilities, 318, today - n.months)
  utility_bills_by_item.each do |item, amount, offset|
    on = (today - n.months) + offset
    log.call(item, amount, on, "#{item.name} for #{on.strftime("%B")}")
  end
end

# THE GROCERIES, FOUR PERIODS OF IT — the drift window exactly. $460 set aside and $460 spent every
# period against a $400 rule, so the observed rate is $60 over the rule and the panel says so. Two
# shops a period rather than one, because that is what a fortnight of groceries is.
(1..4).each do |n|
  opened_on = periods_ago[n]
  allocate.call(groceries, 460, opened_on)
  log.call(supermarket, 230, opened_on + 3, "Supermarket shop")
  log.call(supermarket, 230, opened_on + 9, "Supermarket shop")
end

# THE TRANSIT PASSES THAT STOPPED. Two periods of a fortnightly pass, six and five periods back,
# and nothing since — three complete empty periods is what detector 4 calls dead, and the category
# nets to zero so the rule is the only thing left of it.
[6, 5].each do |n|
  allocate.call(commuter, 60, periods_ago[n])
  log.call(transit_pass, 60, periods_ago[n] + 2, "Fortnightly transit pass")
end

# THE SAVINGS CONTRIBUTIONS. Money the household set aside for its goals, every period, out of the
# same root everything else is funded from — which is the whole of what a savings category is now.
contributions = [[emergency_fund, 100], [vacation, 50], [house_fund, 150], [new_car, 75], [retirement, 150]]

(0..6).each do |n|
  contributions.each { |category, amount| allocate.call(category, amount, periods_ago[n]) }
end

# A weekend of the trip already booked, out of the money set aside for it — and the spending the
# Vacation rule above is measured against.
log.call(vacation_costs, 180, periods_ago[3] + 5, "Flight deposit")

# THE TWO CATEGORIES THAT ARE SPENT AT EXACTLY THE RATE THEY CLAIM. One period's worth in and one
# period's worth out, over the four complete periods the drift detector measures: the rule is
# right, so the panel is silent about them, which is the half of the detector that is only proved
# by a category it declines to report.
(1..4).each do |n|
  allocate.call(medical_copays, 60, periods_ago[n])
  log.call(copay_visits, 60, periods_ago[n] + 4, "Clinic copay")
  allocate.call(prescriptions, 35, periods_ago[n])
  log.call(pharmacy, 35, periods_ago[n] + 6, "Pharmacy refill")
end

# THE PREMIUM SET ASIDE ON TIME, a fortnight ago — the alerts band's whole subject (see above).
allocate.call(renters_insurance, 180, periods_ago[1])

# ---------------------------------------------------------------------------------------------
# THIS PERIOD'S OWN ALLOCATIONS. Everything above is history; these three are what the household
# did with today's pay, and they are what leaves the root short.
#
# `on: today` matters for all three: `HoldingCalculator#period_closed?` measures from
# `last_funded_on`, so a category funded today is current by definition and nothing sweeps out from
# under the states these exist to show.
# ---------------------------------------------------------------------------------------------
allocate.call(rent, 1_500, today)
allocate.call(groceries, 400, today)
allocate.call(dining, 100, today)

# The overspend that puts Dining Out in the red — $180 out of a category holding $100, both entries
# in the period that closed yesterday.
log.call(restaurants, 110, today - 6, "Dinner out")
log.call(restaurants, 70, today - 2, "Dinner out")

# The two closed categories' own spending, inside the period they were funded in.
allocate.call(supplies, 120, periods_ago[1])
log.call(cleaning, 45, periods_ago[1] + 4, "Detergent, paper towels, bin bags")
allocate.call(pet_care, 150, periods_ago[1])
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

# SIDE GIG CHECKING — THE ONLY ACCOUNT IN THE RED, and the shape Home's standing band has a line
# for. `AccountLedger#balance_of` is movements only for an account that is not the pot, so the way
# an account goes negative is a movement OUT of it that its inflows do not cover.
#
# The story is the household's freelance income: $1,300 of invoices routed into the side account,
# then $1,600 moved back to Checking to pay the quarterly estimated tax bill out of the pot,
# because that is where the cash actually leaves (§2). Ordinary, recoverable and entirely legible —
# an account that looks broken for no reason teaches the wrong lesson.
side_gig_income = lane.call("Side Gig Income", :income, "#26C6DA")
invoices = side_gig_income.items.create!(name: "Client Invoice")
deposit.call(invoices, 900, periods_ago[2], "Invoice #114 paid", side_gig)
deposit.call(invoices, 400, today, "Invoice #117 paid", side_gig)

# THE TAX BILL ITSELF — an expense out of what's available, on a category that holds nothing, which
# is also the demo's second GUESSED dated bill for the suggestion engine.
estimated_taxes = lane.call("Estimated Taxes", :expense, "#78909C")
log.call(estimated_taxes.items.create!(name: "Federal Estimate"), 1_600, today - 3, "Q3 estimated tax payment")
move.call(side_gig, checking, 1_600, today - 3)

Rails.logger.debug "Seed data created successfully!"
