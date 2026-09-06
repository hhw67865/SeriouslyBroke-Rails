# frozen_string_literal: true

class Entry < ApplicationRecord
  include ModelSearchable

  belongs_to :item, touch: true
  accepts_nested_attributes_for :item

  # THE MIRROR MOVEMENTS THIS ENTRY CAUSED — income routing's one row, and `dependent: :destroy`
  # so deleting the paycheck deletes the transfer that says where it went.
  #
  # `belongs_to :pool` IS GONE WITH `entries.pool_id` (two-ledger spec §2, Task 8). The column was a
  # per-entry "paid from" override on the pool a category's spending reached, and §2 rules the lane
  # out of existence outright: the pot is where cash leaves, whatever the entry names. Task 1's
  # migration cleared every override in the database before the column went.
  has_many :account_movements, foreign_key: :source_entry_id, dependent: :destroy, inverse_of: :source_entry

  # ** THE ACCOUNT THIS ENTRY IS THE OPENING OF (account-openings spec §2), or nil — which is every
  # ordinary entry there is. ** NOT a lane and not a "paid from": no balance reader looks at this
  # column. It says only that `AccountOpening` wrote this row as the record of what one account held
  # on its opening day, so a correction can find that row again and REWRITE it rather than write a
  # second one. The unique index behind it is the "never a second entry" rule made structural.
  belongs_to :opening_account, class_name: "Pool", optional: true

  # ** ZERO IS A FIGURE ONLY AN OPENING MAY CARRY (fix round — MED-4). ** Every other entry is money
  # that moved and `> 0` is the whole of what makes one, with the sign carried by the category's
  # type. An opening is not money that moved: it is the ANSWER to "what's in it right now", and
  # "nothing" is a real answer — a fresh savings account, or a checking account whose balance the app
  # already tracks exactly. `HomePresenter#awaiting_opening?` reads the EXISTENCE of this row (so
  # that deleting it from the Entries screen puts the question back on the account's card), and
  # without a zero-amount row those two households could never answer at all: they would type their
  # figure, be told the account holds it, and find the question still there on the next render.
  #
  # IT COSTS NOTHING ANYWHERE ELSE. A zero adds zero to `AccountLedger`'s sums, drains no category,
  # and carries no movement (`account_movements` has its own `amount > 0` CHECK, and
  # `AccountOpening#write_movement` writes none for a zero). What it does is exist, which is the
  # whole job.
  validates :amount, presence: true, numericality: { greater_than: 0 }, unless: :opening?
  validates :amount, presence: true, numericality: { greater_than_or_equal_to: 0 }, if: :opening?
  validates :date, presence: true

  # IS THIS ROW AN ACCOUNT'S OPENING RECORD? The one question `entries.opening_account_id` answers,
  # asked by the validation above and by `EntriesController`, which refuses to let this screen
  # re-point such an entry at another account.
  #
  # `has_attribute?` FIRST, and it is the same guard `Budget#keeps_unspent_never_dates` carries for
  # the same reason: two validations above are gated on this method, and
  # `spec/support/schema_rewind.rb` runs whole files against a schema where the column does not
  # exist yet — the world `spec/migrations/account_openings_spec.rb` has to plant its fixtures in.
  # Without it, every `create(:entry)` in that world raises `NoMethodError` out of `valid?`.
  def opening? = has_attribute?(:opening_account_id) && opening_account_id.present?

  # ** THE SENTENCE THE ENTRIES SCREEN SAYS ABOUT AN OPENING ENTRY, IN TWO PIECES AND ONE PLACE
  # (fix round — MED-1). ** The form prints it with the second half as a link to Home; the
  # controller's refusal prints both halves as flat text. Spelled here so the read-only line a user
  # sees and the 422 a crafted POST gets cannot drift into two different explanations of one rule.
  OPENING_DOOR = "edit it from the account card"

  def opening_line = "Opening balance for #{opening_account&.name}"

  def opening_refusal = "#{opening_line} · #{OPENING_DOOR}."

  delegate :user, to: :item
  delegate :category, to: :item

  scope :expenses, -> { joins(item: :category).where(categories: { category_type: :expense }) }
  scope :incomes, -> { joins(item: :category).where(categories: { category_type: :income }) }
  scope :tracked, -> { where(categories: { tracked: true }) }

  # EVERY ENTRY THAT DRAINS ONE CATEGORY — `CategoryLedger::ENTRY_CATEGORY_ID` narrowed to a single
  # id, and THE ONE PLACE THAT NARROWING IS SPELLED (two-ledger spec §4). The port of
  # the pool era's `.reaching_pool`, and it lives on the model for that scope's own reason: two
  # readers ask
  # it — `HoldingCalculator` for the expense term of one category's holdings, and `CategoryLedger`
  # for the same figure GROUPED across a whole screen — so the rule has to be one expression rather
  # than two that happen to agree today. The constant lives on the ledger because that is the class
  # that has to GROUP BY it.
  #
  # WHAT IT ADDS OVER WALKING `item → category` is the funded-since gate: spending dated before the
  # category started holding money drained AVAILABLE and reads there, so it must be absent here.
  # That is the whole difference, and it is why this cannot be `has_many :entries, through: :items`
  # with a comment.
  #
  # The joins are the constant's contract. `item: :category` comes first because the expression
  # reads `categories.funded_since` and `categories.category_type`, and it is the same inner join
  # `.expenses` and `.incomes` carry, so a caller composing this with one of those joins nothing
  # twice; `ENTRY_CATEGORY_JOINS` brings the aliased owner whose timezone the day-boundary
  # comparison re-zones through.
  scope :draining,
        lambda { |category|
          joins(item: :category)
            .joins(*CategoryLedger::ENTRY_CATEGORY_JOINS)
            .where("#{CategoryLedger::ENTRY_CATEGORY_ID} = :id", id: category.id)
        }

  # ** THE CATCH-ALL LANE (computed-claims spec §3.1/§3.2, ruling of 2026-09-03), AND THE ONE PLACE
  # THE PARTITION IS SPELLED. ** A category's claim is the SUM of its rules' claims, so the lanes
  # those rules read have to be a PARTITION of the category's spending rather than a set of
  # overlapping views of it. An item-backed rule owns its item's spending exclusively; the category's
  # one catch-all rule owns everything else.
  #
  # ** WHAT IT COSTS TO LEAVE OUT, MEASURED ON THE DEMO'S OWN Pet Care. ** A $200 catch-all rate rule
  # beside a $600 vet bill on the Vet item, and a $300 payment of that bill: the payment lowered the
  # bill's built-up by $300 AND the rate rule's claim by $300, so Σ claims fell by $600 while the
  # user's total money fell by $300 — and `free`, which is `total − Σ claims`, ROSE by $300. Paying a
  # bill made the app say there was more money to spend.
  #
  # A SUBQUERY OVER `budgets`, not a join: `entries.item_id` is NOT NULL and the inner
  # `where.not(item_id: nil)` keeps a NULL out of the `NOT IN` list, which is the one shape that
  # would silently match nothing. It is not scoped to a category because it does not need to be — a
  # rule may only name an item OF the category it funds (`Budget#item_must_belong_to_category`), so
  # an item that carries a rule carries its OWN category's rule.
  #
  # BOTH READERS COMPOSE IT: `ClaimCalculator`'s self-query for one rule and `ClaimLedger`'s grouped
  # statement for a whole user, which is why it is a scope here rather than a clause in either.
  scope :on_unruled_items, -> { where.not(item_id: Budget.where.not(item_id: nil).select(:item_id)) }

  # Define searchable fields using the DSL
  searchable :description, label: "Description"
  searchable :date, type: :date, label: "Date"
  searchable :item, through: :item, column: :name, label: "Item"
  searchable :category, through: [:item, :category], column: :name, label: "Category"
  # `searchable :pool` IS GONE with `Entry.in_pool_named` and the column it resolved (Task 8). It
  # was the DSL's one `:scope` field and its worked example in
  # `docs/searchable-system-reference.md`; the type stays in the DSL — a scope-backed field is the
  # only way to search across a rule the SQL spells and an association cannot — and the reference
  # now documents it without a live caller.

  # INCOME ROUTING (main-account spec §4), THE MIRROR AND NOT THE LANDING.
  #
  # The income entry itself ALWAYS lands in main — income lands in the pot and is allocated out of
  # it (§2) — and nothing here moves it. What a user picking "Ally" on the entry form is recording is
  # that the money did not STAY in main, and this writes exactly that: ONE `transfer` movement
  # main → Ally for the full amount, carrying this entry as `source_entry` so an edit finds it
  # again (`dependent: :destroy` on the association already covers the delete).
  #
  # `kind_transfer` IS THE ONLY KIND LEFT, AND THE SCOPE IS KEPT ANYWAY. It was load-bearing while
  # `pool_movements` also held a distribution's allocation and sweep rows — they carry a
  # `source_entry` too, so a routing sync that went by the link alone deleted the period's envelope
  # split every time somebody corrected a paycheck's amount. The distribution's rows are
  # `allocations` now and `account_movements_are_transfers` holds the rest at the database, so the
  # filter is a tautology today; it stays because it is the sentence that says WHICH rows this
  # method owns, and a second kind on this table would otherwise silently join them.
  #
  # IDEMPOTENT BY CONSTRUCTION rather than by branching: every path clears first, so re-routing
  # replaces, routing to main removes, and calling it twice with the same account leaves one row.
  # A user with no main account routes nothing — there is nothing for the money to be mirrored OUT
  # of, and inventing a source pool here would move money the user never had.
  def route_income_to!(account)
    routing = account_movements.kind_transfer
    main = user.default_account
    routing.destroy_all
    return if account.blank? || main.blank? || account == main

    account_movements.create!(
      from_pool: main,
      to_pool: account,
      amount: amount,
      date: date,
      kind: :transfer
    )
  end

  # WHERE THE FORM'S "Lands in" SELECT OPENS ON AN EDIT — the account this entry was routed to, or
  # nil for one that stayed in main. The absence of a routing movement IS "main", so nil is the
  # honest answer rather than a missing one, and the form falls back to the user's main itself.
  #
  # `sole` AND NOT `first`, WHICH MAKES THE ONE-ROW INVARIANT LOAD-BEARING RATHER THAN ASSUMED.
  # #route_income_to! clears before it writes, so an entry has AT MOST one routing movement by
  # construction — and `first` would quietly pick one of two if that ever stopped being true, on an
  # unordered query, handing the form a destination that half the app disagreed with. `sole` raises
  # instead. The empty case is checked FIRST because it is not a violation of anything: `sole`
  # raises on zero rows as loudly as on two, and "this income stayed in main" is the ordinary
  # answer, not an error. `to_a` so the two questions cost one query between them.
  def routed_account
    routing = account_movements.kind_transfer.to_a
    return if routing.empty?

    routing.sole.to_pool
  end
end
