# Home sections, lane names, the fund cap, and Activity

Henry, 2026-09-11. Four follow-ups from reviewing the Home and Budget layout. The "what" is
`docs/decisions.md` §4 and §10; this is the "how".

## 1. What changes

| Area | Change |
|---|---|
| Home | "This period" becomes two sections, Budget ("$X claimed") and Savings ("$Y owed"), each with its total |
| Rows | an item-less rule is named "Everything else in <Category>" or "All of <Category>", on Home and Budget |
| Rules | a fund may carry a cap; the walk stops adding at the cap; the form, preview and rows say so |
| Activity | a new page under Look back listing entries, transfers and adjustments newest first, with Edit and Remove |

## 2. Home sections

`app/views/home/_this_period.html.erb`: the heading row keeps its counts and the legend. Beneath it
two `<section>`s: `data-budget-section` with a header "Budget · <claimed> claimed"
(`presenter.budget_claim`) holding the category blocks and the unbudgeted rows; `data-savings-section`
with "Savings · <owed> owed" (`presenter.savings_claim`) holding the savings blocks, rendered only
when there is a targeted account. The empty-state sentence stays under the Budget section.

## 3. Lane names

`HomeHelper#lane_words(line, rows)`: the item's name when the rule names one; otherwise "Everything
else in <category>" when `rows.size > 1`, else "All of <category>". Home's row prints it
(`_this_period`, `block.rows`); Budget's row prints it (`_category_open`, `row.lines`). The
`data-rule-row` and `data-rule` hooks keep `ClaimLine#name` / `rule_name`, so specs keyed on "Whole
category" change only where they assert visible text. `ClaimLine::WHOLE_CATEGORY` stays as the hook
value and nothing else.

## 4. The fund cap

Schema: `AddCapToRules` — `cap` money nullable; check `cap IS NULL OR (keeps_unspent AND cap > 0::money)`.

`Rule`: `validates :cap, numericality: { greater_than: 0 }, allow_nil: true`; `validate :cap_needs_a_fund`
(a cap only on a rule that keeps unspent); `def capped? = cap.present?`.

`RuleForm`: `:cap` in `FIELDS` and `from`; `schedule_columns` writes `cap: keeps? ? cap.presence : nil`;
`RULE_ERROR_FIELDS` gains `cap: :cap`.

`ClaimCalculator`, fund arms only:
```
planned(P)  = capped: min(amount, max(cap − built_up, 0))    else amount
accrued(P)  = capped: min(built_up + planned + Σadj(P), cap)   else built_up + planned + Σadj(P)
target      = capped: cap                                      else nil
```
`ClaimLine#bar?` then draws a capped fund against its cap; `fund_short?` stays dated-only. `Rule#ask`
is unchanged (the steady figure is the amount); `per_period` is `planned`, so a full fund takes
nothing this period.

Words: `figure_words` for a capped fund is "built up $X of $Y"; `when_words` for a capped fund at
its cap is "full at $Y", else "+$amount a period"; the Budget row's steady line reads "full at $Y"
when a capped fund's `per_period` is zero. `rule_preview_holding_sentence` for a capped fund: "It
builds up to $Y, then stops asking until some of it is spent."

Form: a "Stop at" money field inside the keeps block, hint "optional — once the pile reaches this,
the rule stops asking until you spend from it", disabled alongside keeps under "By a date".

## 5. Activity

Route `get "activity" => "activity#show"`; nav "Look back": Activity, Reports.

`ActivityPresenter.new(user:, page:)`:
```ruby
Row = Data.define(:kind, :date, :created_at, :words, :amount, :edit_path, :remove_path, :remove_confirm)
# kind: :entry | :transfer | :adjustment; amount signed for an entry (income +, expense −)
```
Rows come from the user's entries, the transfers touching the user's accounts, and the adjustments on
the user's rules and accounts, mapped to `Row`s, sorted by `[date desc, created_at desc]`, then
`Kaminari.paginate_array(rows).page(page).per(50)`. Words: entry → "<item> · <category>";
transfer → "<from> → <to>"; adjustment → "<source name> · <reduced | topped up | took back | set aside>".
`edit_path` is `edit_entry_path` for an entry, nil otherwise. `remove_path`: `entry_path`,
`transfer_path` (new destroy), `adjustment_path`. Every remove carries `return: "activity"` and the
redirect honours it: `EntriesController#destroy` via `previous_url: activity_path`,
`TransfersController#destroy` (new; finds through `current_user.accounts`; redirects to
`activity_path`), `AdjustmentsController#back_to` gains an `"activity"` arm.

View `activity/show.html.erb`: page header "Activity", subtitle "Everything that happened, newest
first."; a table (kind, date, what, amount, actions) that folds to cards below `md` like the entries
table; kaminari links at the foot; an empty state.

## 6. Testing

Presenter specs for `lane_words`, the capped walk (reaches the cap, stops, draws down, rebuilds; an
adjustment cannot push past the cap), `ActivityPresenter` order and words. Model and form specs for
the cap. System specs: Home's two sections and totals; the lane names on Home and Budget; the rule
form's cap field and preview sentence; Budget's "full at" row; Activity renders each kind and
removes a transfer and an adjustment from it.

## 7. Commits

1. Home sections and lane names.
2. The fund cap.
3. Activity.
4. Docs, the whole suite, the visual check.
