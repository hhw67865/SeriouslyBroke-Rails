# Decisions

How the app works and what has been decided. This file states the current direction only. It never
records what used to be true or what was considered and dropped. When a decision changes, the old
sentence is replaced, not kept.

## 1. Vocabulary

- **Checking** is the user's main account. Every claim is on checking. Expenses leave it. Income
  always lands in it.
- **Savings** are every other account. An account exists for one reason: money that has left
  checking on purpose. There is no other kind of account.
- **Budget** is the sum of what the rules ask per period. Rules are the pieces of a budget.
- **Savings**, as a figure, is the sum of what the savings targets ask per period.
- **Claim** is what one rule or one account currently holds on checking. The **budget claim** is
  the rules' claims summed; the **savings claim** is the accounts' claims summed. **Claimed** is
  both together.
- **Free** (free to spend) is checking minus claimed.
- **Ask** is what one rule or target costs per period. There is one word for this, not three.
- **Typical income** is the mean of regular income over the last two complete periods. It is
  derived, never typed.
- **Leftover** is typical income minus savings minus budget.

## 2. Money

- Everything shown about money is derived at read time from the tables. Nothing is cached.
- Budgeted money never leaves checking. A rule says what a category may spend, and the money for
  it sits in checking until it is spent. Nobody moves money to another account to earmark it.
- The only reason money leaves checking for another account is savings, and that transfer is what
  fulfils a savings claim.
- Income always lands in checking. Money reaches a savings account only by a transfer the user
  makes. An entry has no account.
- Balances: an account's balance is its opening balance, plus income and minus expenses (checking
  only), plus transfers in, minus transfers out.
- Saved over a range, per account, is transfers in minus transfers out dated in that range. Across
  all savings it is the same sum over every savings account, so transfers between two savings
  accounts cancel. Opening balances and balance corrections are never "saved in a range".
- The verb for money moving between accounts is **transfer**, on every screen.
- Amounts are positive on entries, transfers and rules. Adjustments are signed and never zero.

## 3. Periods

- A user declares a cadence (weekly, biweekly, semimonthly, monthly) and an anchor date. Without a
  cadence the calendar month is the period.
- Per-period figures mean nothing without a cadence, so comparing the budget to income requires
  one declared.
- Changing cadence offers to scale every per-period amount by the ratio of periods per year.

## 4. Rules

- A rule lives on an expense category. Its lane is its item's entries when it names an item, else
  the category's entries on items that have no rule of their own. One item-less rule per category;
  one rule per item.
- A rule has a **kind**: bill, usage or choice. The kind sets the give-way order (§9).
  - **Bill**: a must. A set amount on a date, once or every so many months. You can't spend less
    on it by using less. Rent, insurance, a loan payment.
  - **Usage**: something you have to spend on, but how much depends on how you use it. You can
    bring it down. Utilities, groceries, fuel.
  - **Choice**: something you choose to get. Not a necessity; you could go without. Eating out,
    hobbies, clothes.
  These definitions live on the rule form, where a kind is picked. Home carries only a legend.
- What a rule **takes this period** is the calculator's planned figure for the current period,
  which depends on the day: a dated bill that just started has nothing behind it and takes more per
  period until it is caught up. Its **steady** figure is what it asks per period once caught up.
  The Budget page shows both; the "fits" verdict uses the steady figure.
- A rule has a **shape**, decided by two columns:
  - **rate**: per period, does not keep unspent. Claims `max(0, amount − spent)` this period only.
  - **fund**: per period, keeps unspent. Each period adds the amount; what is unspent carries.
  - **dated**: an amount by a date, once or rolling every N months. The claim builds toward the
    next open due date so it is there on the day.
- A dated bill's due dates are a series: the anchor date stepped by the interval, forward and back,
  starting at the first due date on or after the rule's start. A one-off is a series of one.
- Spending on a dated rule's lane settles due dates in order, earliest open first, whether it
  lands before or after the day. The next due date is the first one not yet covered. Paying ahead
  settles further due dates; there is no cap.
- A one-off is settled at its target. Anything spent past that is just spending.
- Overspending never carries as debt. Next period starts from the rule's own figure.
- A dated rule is a budget, never savings. Saving for a car repair, a holiday or a house is
  budgeting an expense that is coming, and belongs on a category.
- `starts_on` is the first day whose spending counts.

## 5. Savings targets

- A savings target is a promise that an account is owed money from checking. It is not a rule. It
  has no date, no ceiling and no end. You always want savings.
- An account's targets live in one table, `savings_targets`. Each row is one source of owed money
  and has its own `starts_on`:
  - a **target** row: no item, an amount per period. It asks whether or not income came in.
  - a **share** row: an income item and a percent. It asks only when an entry lands on that item,
    from that day.
- A row with an item carries a percent and nothing else. A row without an item carries an amount
  and nothing else. An item never asks for a fixed sum.
- An account can take shares from many items. An item can feed many accounts. One item's percents
  across accounts sum to at most 100.
- An account's targets sum into one claim. The account carries one flag, `keeps_extra`, that
  decides how extra carries:
  - **keeps extra** (a minimum): owed since the start minus arrived since the start, floored once.
    Moving five periods' worth at once means no claim for five periods.
  - **every period**: floored each period. Extra in a period is just extra. A shortfall carries, so
    $100 against $200 owed leaves $300 asked next period.
- In both modes a shortfall carries. Unmoved money is still in checking and still owed.
- Fulfilment is transfers into the account dated on or after its earliest `starts_on`. Nothing is
  automated: a target claims, and the user moves the money. Taking money back out of savings is
  using it, not un-saving it, and does not reopen the claim.
- A new row's `starts_on` defaults to today. Editing an amount or percent leaves `starts_on`
  alone; it is an editable field, so restarting is a deliberate act.
- Checking never carries a target.
- A savings target's ask per period is its amount, or its percent of that item's typical income.
- The form shows what percent of typical income a fixed amount is, as a hint. Percent of typical
  income is never a target itself, because typical income moves and a claim must be a fixed sum.

## 6. Claims, claimed, free

- Two calculators, one interface: one rule's claim, one account's claim. Each is handed its rows
  and returns a claim and an ask.
- One ledger produces one list of claims for a user, each with its source, name, kind, claim, ask
  and whether it can be cut. Home, the Savings page, the sacrifice page and the Budget tiles read
  that list and never ask what record is behind a claim.
- Claimed is the budget claim plus the savings claim. Free is checking minus claimed.

## 7. Adjustments

- An adjustment is a signed amount on a date, on one claim source. The calculator adds it to what
  that source accrued in the period containing the date. The source itself is untouched.
- An adjustment's date must fall inside what its source counts, up to today.
- On a rule: **top up** / **reduce** on a per-period rule, **set aside** / **take back** on a dated
  rule, and **skip this period**, which is minus exactly what accrued this period.
- On an account: **reduce** and **skip this period** only. Always negative. There is
  no top-up on savings, because with no ceiling, saving more is just moving more.
- Adjustments are polymorphic over rule and account.
- An adjustment is a change to what is owed right now, made because this period needs it and the
  underlying rule or target should not change. So it lives where "right now" is shown: on Home,
  each rule row in "This period" carries Adjust; on the Savings page, the "owed now" cell does. The
  Budget page is the stable foundation and carries no Adjust; it shows the rules and what they
  take.

## 8. The two problems

- **Checking is not enough** shows as free going negative. It is a this-period problem and the fix
  is a this-period record: reduce or skip. The plan stands and next period starts clean.
- **Income is not enough** shows as leftover going negative. It repeats every period, so it cannot
  be adjusted away. The fix is editing a rule or a savings target, and the sacrifice page is where
  that is worked out.
- The second problem shows up as the first when ignored. Home shows both signals side by side so
  that someone skipping every period can see the real cause.

## 9. Give-way order

- When money is short, claims give way in this order: **choice**, then **usage**, then
  **savings**, then **bill**. A bill is what it is.
- Savings is filled first and cut late, but it is cuttable. The sacrifice page lists savings in its
  own section, one row per target: a fixed target can be cut to a lower amount, a share to a lower
  percent.
- Within categories, `priority` is the fill order: 0 fills first, the highest number gives way first.

## 10. Screens

- **Nav**, in four groups: Today (Home, Entries, Calendar), Plan (Budget, Savings), Look back
  (Reports), Set up (Categories, Settings). A page is one of three things: an answer to read, a
  thing you do, or a thing you set up, and it is never two of them.
- **Home** (`/`) is the full picture, headed by the day and where it sits in the period. Four
  tiles: free to spend (after everything claimed is set aside; no per-day pace), checking with what
  was spent this period, claimed with its budget and savings split, and savings with what is owed.
  Then the trouble strip, only when something is wrong. Then "Coming up": every dated rule due in
  the next 30 days with its date, amount and state (ready, set aside so far, on track). Then "This
  period": one block per ruled category and per savings account with a target, each rule or target
  as a row with its bar and its Adjust disclosure, under a header that carries the kinds legend in
  give-way order. An adjustment is the one thing written from Home; everything else links out.
- **Savings** (`/savings`): checking at the top with balance,
  claimed (budget and savings as its two lines) and free; then each savings account with its
  targets in words ("$200 a period, plus 10% of Paycheck"), what it is owed now, a Transfer button that
  writes a transfer from checking for exactly that amount, dated today, in one click, and its
  adjust panel. The Transfer money drawer stays for any other amount.
  An account with no target reads as such. Account CRUD stays under `resources :accounts`.
- **Account form**: name, balance today, the keeps-extra choice as two sentences,
  and a list of target rows, each an amount or an item-and-percent, with its start date.
- **Budget** (`/budget`) is where rules are set up, and keeps its shape: the tiles, then every
  expense category as a collapsible section with its reorder controls, name, rule count and kind
  dots, and inside it the rules table and a "New rule in <category>" door. No Adjust here.
  Three things change. The Adjust disclosures and the list of this period's adjustments move to
  Home. The rules table's "Now" column becomes "Takes this period", the calculator's
  planned figure for today, with the steady figure beneath it; a collapsed section shows its
  categories' total take this period. And no claimed figure appears anywhere on the page; that is
  Home's. The tiles read "You bring in X. Where it goes: Y this period (Z a period once every bill
  is caught up). That leaves W." with the verdict on the steady figures. A category with no rule is
  a plain row with "Give it a rule".
- **Rule form** (`/rules/new`, `/rules/:id/edit`): as built. Step 3's three options carry the kind
  definitions from §4 as their help text; nothing else on the form changes.
- **Sacrifice** (`/sacrifice`): what would have to give when the budget and savings need more than
  typical income. Two sections: the budget's rules, then each savings target. Rolling bills are
  fixed. A share is cut by percent, a fixed target by amount.
- **Entries**: the form has no account picker; income lands in checking.
- **Items, Categories, Calendar, Reports, Settings**: as built.

## 11. Testing

- Logic is proven in model, service and presenter specs. A system spec proves a page renders its
  figures once, and every real interaction.
- Rack::Test by default; `:js` only when JavaScript is needed. One browser per process. No `sleep`.

## 12. Out of scope

- Suggestions of any kind.
- Writing transfers automatically, on income or at a period boundary.
- Income landing anywhere but checking.
- Spending from any account other than checking.
- A percentage of typical income as a savings target.
- A top-up adjustment on savings.
- Versioning a target's edits. Moving one row's `starts_on` while others keep theirs can make an
  account look ahead, because fulfilment is pooled. That is accepted.
