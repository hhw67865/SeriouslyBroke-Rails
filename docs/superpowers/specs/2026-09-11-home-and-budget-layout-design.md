# Home, Budget and the Nav: one job per page

Henry, 2026-09-11. The pages grew around the claim system one feature at a time, and Home ended up
a second Budget page. This spec regroups the nav, makes Home the full picture, keeps Budget as the
setup page that says what each rule takes today, and puts the kinds where a kind is picked. The
"what" is `docs/decisions.md` §4 and §10; this file is the "how". Mockups:
https://claude.ai/code/artifact/8df83bbb-e085-4609-ba34-a5bae0b6de9f

## 1. What changes

| Page | Before | After |
|---|---|---|
| Nav | Main / Management / Analysis | Today / Plan / Look back / Set up; Calendar under Today |
| Home | money row, manage-accounts line, runway, trouble, this-period rule blocks | four tiles, trouble, Coming up, this-period blocks incl. savings, kinds legend |
| Budget | tiles, category sections with claimed and Adjust | same sections; the rules table says what each rule takes this period with the steady figure beneath; no claimed, no Adjust |
| Adjust | on Budget rule rows and Savings owed cells | on Home this-period rows and Savings owed cells |
| Rule form | step 3 with one-line kind hints | step 3 with the kind definitions as its help text; nothing else |

Nothing about the model or the calculators changes. `ClaimCalculator#planned_this_period` is the
"takes this period" figure; `#ask` is the steady one; both exist.

## 2. Nav

`app/views/shared/_sidebar.html.erb`: four `nav_section` calls, titles "Today", "Plan", "Look
back", "Set up", with the links in `decisions.md` §10 order. Icons stay. The navbar spec asserts
the four titles and the link order.

## 3. Home

`HomePresenter` keeps its ledger reads and gains:

```ruby
Tile      = Data.define(:free, :checking, :spent_this_period, :claimed, :budget_claim, :savings_claim, :savings_total, :savings_owed, :savings_count)
Upcoming  = Data.define(:line, :due_on, :amount, :state, :set_aside)   # state: :ready | :short | :building
def tiles
def upcoming            # ClaimLine rows with next_due_on within today..today+30, sorted by date
def savings_blocks      # SavingsLine per targeted account, from a SavingsPresenter-style read
def kinds_legend        # [[:choice, "Choice"], [:usage, "Usage"], [:savings, "Savings"], [:bill, "Bill"]]
```

`upcoming` replaces `runway`: a row is `:ready` when `built_up >= target`, `:short` when its due
date is inside the current period and it is not, else `:building` with `set_aside = built_up`.
`spent_this_period` is expense entries in the current period. `savings_owed` is
`claim_ledger.savings_claim`.

Views under `app/views/home/`: `_tiles.html.erb` (replaces `_money`), `_upcoming.html.erb`
(replaces `_runway`), `_this_period.html.erb` gains the legend in its header and a savings block
per targeted account after the category blocks, reusing the row anatomy with the account's target
words as the row name and the owed figure as the bar. `_manage_accounts.html.erb` and the pace line
are deleted. The header is `page_header(title: today.strftime("%A, %B %-d"), subtitle: "Day N of M
in this period · next payday <date>")`, from `period_progress`.

`_trouble` and `_shortfall` stay as they are.

The Adjust disclosure moves from `budget_page/_adjust` to `home/_adjust`, rendered under each rule
row in `_this_period` (and each savings block's row, reusing `savings/_adjust`), with this period's
adjustments listed beneath it as the Budget page listed them. `HomePresenter` therefore loads
`adjustments_this_period` the way `BudgetPagePresenter` does today. `AdjustmentsController`'s
`back_to` for a rule becomes `root_path` (anchored to the category block, `#block-<category id>`),
and `refuse_on_budget_page` becomes a `HomePageState#refuse_on_home` that re-renders Home with
the flash.

## 4. Budget

The page keeps `_category_row` and `_category_open` as they are, including the reorder controls,
the rules table and the per-category `new_rule_path(category_id:)` door. The `_adjust` render and
the adjustments list leave `_category_open` (they move to Home, §3), as does
`BudgetPagePresenter#adjustments_this_period`.

`BudgetPagePresenter`:

```ruby
Tiles = Data.define(:budget, :budget_now, :savings, :segments, :income, :cadence, :leftover, :leftover_now, :declared, :fits)
CategoryRow gains :takes_now     # Σ line.per_period over its lines
def budget_now       # Σ calculator.planned_this_period over rules
def leftover_now     # income − savings − budget_now
```

`fits` and `underwater?` keep using `budget` (steady). The tiles partial prints `budget_now` as the
"Where it goes" figure labelled "this period", the segment bar from the steady overview as now, and
"Z a period once every bill is caught up" beneath; the leftover tile keeps the steady verdict and
adds "This period leaves W while <rule> catches up" when `leftover_now` differs.

In `_category_open`, the "Now" column header becomes "Takes this period" and the figure is
`line.per_period` (already on `ClaimLine`) with `line.rule.ask` beneath as "$Y a period once caught
up", or "same every period" when they are equal. `figure_words` moves out of that column into the
"When" cell where it says what is behind the rule ("nothing behind it yet · 10 periods", "$500 set
aside · 2 periods to Oct 21"). `CategoryRow#claimed` and every "claimed" figure on the page go; the
collapsed header shows `takes_now` instead. A category with no rule stays a row with "Give it a
rule".

## 5. Rule form

Unchanged in layout and behaviour. In `app/views/rules/_form.html.erb` step 3, the `type_help`
hash's three strings become the §4 definitions, one sentence each plus the examples and the
give-way clause, and move to `BudgetPageHelper::KIND_DEFINITIONS` so Home's legend and the form
read one source. The preview is untouched.

## 6. Testing

Presenter specs for `tiles`, `upcoming` (ready / short / building; the 30-day window edge),
`budget_now`, `leftover_now`. System specs: navbar order; Home renders the four tiles, an upcoming
row in each state, a savings block and the legend; Budget renders a rule line's two figures and the
tiles' two figures; the rule form shows the three definitions.

## 7. Commits

1. Nav regroup and its spec.
2. Home: presenter, tiles, upcoming, this-period savings blocks and legend, Adjust moved here with its controller redirects, deletions, specs.
3. Budget: presenter figures, tiles, rule lines, Adjust removed, specs.
4. Rule form: kind definitions from one shared source, specs.
5. Docs: decisions.md screens section is already the target; coding-standards names the new
   presenter members.

## 8. Out of scope

- Any change to Savings, Sacrifice, Entries, Calendar, Reports, Categories, Settings.
- A per-day pace figure anywhere.
- Judging "fits" on this period's take.
