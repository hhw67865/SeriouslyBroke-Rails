# frozen_string_literal: true

require "rails_helper"

# The wire contract of the Home add-account door: `bank_account[name]` is the only writable
# ATTRIBUTE, and the pool type is a server fact. Pinned here rather than in a system spec —
# no user submits a crafted param through Chrome, and this layer can see the status codes.
#
# ** `bank_account[balance]` IS PERMITTED AND IS NOT AN ATTRIBUTE (account-openings spec §3). ** The
# add row asks for a name and what is in the account in one submission, because for the user that is
# one act; the figure never touches the record, it is handed to `AccountOpening`, which writes the
# same opening record every other row on that card writes.
RSpec.describe "BankAccounts", type: :request do
  let(:user) { create(:user) }
  let!(:checking) { create(:pool, :account, user: user, name: "Checking") }

  before { sign_in user, scope: :user }

  describe "POST /bank_accounts" do
    it "creates an account pool from the name alone", :aggregate_failures do
      post bank_accounts_path, params: { bank_account: { name: "Ally Savings" } }

      pool = user.pools.find_by(name: "Ally Savings")
      expect(pool).to be_pool_type_account
      expect(response).to redirect_to(root_path)
    end

    # ONE CRAFTED POST, ASKED TWICE. Every attribute a Pool carries that a caller could want is on
    # it at once, because a permit list is only proven by the params it drops TOGETHER — a request
    # that smuggled one of these would smuggle the rest. The two examples below split what the
    # dropping protects, not the request: the first is about what the pool IS and where it sits,
    # the second about the two figures the budget reads off it.
    def post_crafted
      post bank_accounts_path,
           params: {
             bank_account: {
               name: "Sneaky",
               pool_type: "savings",
               account_id: checking.id,
               priority: 9,
               target_amount: 500
             }
           }

      user.pools.find_by(name: "Sneaky")
    end

    # THE COLUMNS THE CRAFTED PAYLOAD NAMES ARE GONE (two-ledger spec §5, Task 8) — `account_id`,
    # `priority` and `target_amount` are dropped and `pool_type` has one member — so the pair of
    # examples that read them back is one example about the only thing left to get wrong. The
    # payload still carries all four, because what is under test is that a permit list narrowed to
    # `[:name]` ignores whatever arrives beside it.
    it "keeps the pool's type the server's own" do
      expect(post_crafted).to be_pool_type_account
    end

    # ** THE BALANCE ARM: ONE SUBMISSION, TWO WRITES, AND THEY LAND TOGETHER OR NOT AT ALL. **
    it "opens the account at the balance it was added with", :aggregate_failures do
      post bank_accounts_path, params: { bank_account: { name: "Ally Savings", balance: "500" } }

      ally = user.pools.find_by(name: "Ally Savings")
      expect(response).to redirect_to(root_path)
      expect(ally.opened_on).to eq(user.today)
      expect(AccountLedger.new(user).balance_of(ally)).to eq(500)
    end

    # A BLANK BALANCE IS NOT AN OPENING OF ZERO: "I don't know yet" and "it holds nothing" are
    # different answers, and only the second is a record. The account keeps its row in the card.
    it "leaves an account added with no balance still to answer", :aggregate_failures do
      post bank_accounts_path, params: { bank_account: { name: "Ally Savings", balance: "" } }

      expect(user.pools.find_by(name: "Ally Savings").opened_on).to be_nil
      expect(Entry.where.not(opening_account_id: nil)).to be_empty
    end

    # THE REFUSED HALF TAKES THE OTHER WITH IT — a mirror cannot be overdrawn (§4), and an account
    # left behind with no balance would be a row the user did not ask for.
    it "writes no account at all when the balance is refused", :aggregate_failures do
      post bank_accounts_path, params: { bank_account: { name: "Ally Savings", balance: "-50" } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(user.pools.find_by(name: "Ally Savings")).to be_nil
      expect(response.body).to include("can&#39;t be negative")
      expect(response.body).to include('value="Ally Savings"')
    end

    it "answers 422 with nothing written when the name is refused", :aggregate_failures do
      post bank_accounts_path, params: { bank_account: { name: checking.name.downcase } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(user.pools.count).to eq(1)
    end

    it "makes the first account the main account, and only the first", :aggregate_failures do
      user.update!(default_account: nil)
      post bank_accounts_path, params: { bank_account: { name: "First" } }
      expect(user.reload.default_account.name).to eq("First")

      post bank_accounts_path, params: { bank_account: { name: "Second" } }
      expect(user.reload.default_account.name).to eq("First")
    end
  end

  # ── THE RENAME AND DELETE DOORS, ARRIVED FROM `spec/requests/pools_spec.rb` (Task 7).
  #
  # That file is deleted with the route it pinned. Its two examples described the pool form's own
  # contract — "assigns the pool type, the parent account and the priority" on POST /pools, and
  # "moves a pool to another account" on PATCH — and neither describes anything that still exists:
  # there is one kind of pool now, it sits inside nothing, and `priority` moved onto the category.
  # What survives is that an account can be renamed and deleted, which is the half of the pool
  # edit screen this resource absorbed.
  describe "PATCH /bank_accounts/:id" do
    def patch_crafted
      other = create(:pool, :account, user: user, name: "Ally")

      patch bank_account_path(checking),
            params: {
              bank_account: {
                name: "Checking",
                pool_type: "savings",
                account_id: other.id,
                priority: 9,
                target_amount: 500
              }
            }
    end

    it "renames the account", :aggregate_failures do
      patch bank_account_path(checking), params: { bank_account: { name: "Everyday Checking" } }

      expect(checking.reload.name).to eq("Everyday Checking")
      expect(response).to redirect_to(root_path)
    end

    # THE SAME CRAFTED PAYLOAD AS THE CREATE DOOR ABOVE, ON THE OTHER VERB. A permit list narrowed
    # for `create` and forgotten for `update` is the ordinary way this contract comes apart, and
    # `pool_type` is the one that matters: a "bank account" talked into `savings` would fail the
    # database's `pools_are_accounts` CHECK on its next save.
    it "keeps everything but the name the server's own", :aggregate_failures do
      patch_crafted

      checking.reload
      expect(checking).to be_pool_type_account
      expect(checking.name).to eq("Checking")
    end

    it "answers 422 with nothing written when the name is refused", :aggregate_failures do
      patch bank_account_path(checking), params: { bank_account: { name: "" } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(checking.reload.name).to eq("Checking")
    end

    # THE SCOPE IS `current_user.pools.accounts`. A stranger's id is the ordinary 404; the
    # `.accounts` half no longer has a second shape to exclude, because every pool is an account
    # (Task 8) — the example that planted a non-account pool of the user's own is deleted with the
    # shape, and the clause is kept because it is what the route's own name promises.
    it "404s on another user's account", :aggregate_failures do
      stranger = create(:pool, :account, user: create(:user), name: "Theirs")

      patch bank_account_path(stranger), params: { bank_account: { name: "Mine" } }

      expect(response).to have_http_status(:not_found)
      expect(stranger.reload.name).to eq("Theirs")
    end
  end

  describe "DELETE /bank_accounts/:id" do
    it "deletes the account", :aggregate_failures do
      ally = create(:pool, :account, user: user, name: "Ally")

      delete bank_account_path(ally)

      expect(user.pools.find_by(name: "Ally")).to be_nil
      expect(response).to redirect_to(root_path)
    end

    # THE POOL ERA'S REFUSAL EXAMPLES ARE DELETED WITH THE REFUSALS (two-ledger spec §5, Task 8). One
    # planted a CATEGORY pointing at the account (`has_many :categories, dependent:
    # :restrict_with_error`) and one a POOL sitting inside it (`has_many :child_pools`); neither
    # association exists, because neither column does. The second was the console-only pin this file
    # kept expressly until the drop, and the drop is here.
    #
    # WHAT DELETING AN ACCOUNT DOES is the first example below: `movements_in`/`out` are
    # `dependent: :destroy`, so an account's transfers go WITH it and the money main had moved into
    # it returns to the pot.
    #
    # THE REFUSAL IS REPORTED, NOT SWALLOWED, and there is one again (final fix wave, C-1):
    # `Pool#main_account_is_not_deletable` halts the callback chain and writes a sentence onto
    # `:base` rather than raising, so a controller that ignored `#destroy`'s return value would
    # redirect with "deleted." over a row still sitting in the database. The flash below is what
    # pins that the controller reads it.

    it "destroys the account's movements rather than moving them anywhere", :aggregate_failures do
      ally = create(:pool, :account, user: user, name: "Ally")
      create(:account_movement, from_pool: checking, to_pool: ally, amount: 500, date: Date.current)

      expect { delete bank_account_path(ally) }.to change(AccountMovement, :count).by(-1)
      expect(user.pools.find_by(name: "Ally")).to be_nil
    end

    # ** DELETING AN ANSWERED ACCOUNT (fix round round 2 — item 4). ** It used to raise
    # `PG::ForeignKeyViolation` against `entries.opening_account_id`; the record goes with the
    # account now, both halves of it.
    #
    # ** AND THE FLASH TELLS THE TRUTH ABOUT THE MONEY, WHICH IS TWO DIFFERENT TRUTHS. ** An opening
    # entry and its transfer CANCEL on main — that is what made saving an account self-contained —
    # so an account funded entirely by its own opening returns nothing and the pot does not move. A
    # flash promising "$500 is back in checking" would be false for exactly the accounts this fix is
    # about. Re-derived: $3,000 of income, Ally opened at $500, pot $3,000 before and after.
    it "deletes an answered account without promising money back", :aggregate_failures do
      ally = create(:pool, :account, user: user, name: "Ally")
      income = create(:category, :income, user: user, name: "Salary")
      create(:entry, item: create(:item, category: income), amount: 3_000, date: Date.current)
      AccountOpening.new(user, ally, balance: "500").save

      delete bank_account_path(ally)

      expect(response).to redirect_to(root_path)
      expect(flash[:notice]).to eq("Ally deleted.")
      expect(Entry.where.not(opening_account_id: nil)).to be_empty
      expect(AccountLedger.new(user).pot).to eq(3_000)
    end

    # ** THE CRAFTED DELETE ON MAIN (final fix wave, C-1). ** Home renders no Delete button on main's
    # card, and a button is a rendering: this is the door the model's refusal is actually behind. The
    # request spec is where it belongs because what is under test is a status, a flash and an
    # unchanged table — none of which Capybara's driver can see.
    #
    # THE FIXTURE IS THE WHOLE REGRESSION IN MINIATURE. `checking` is main (the pool factory makes
    # the first account the user's default, exactly as `#create` does), the movement runs main → Ally
    # the way both writers in the app write it, and the entry gives the pot something to hold. A
    # successful destroy takes the movement with it, nullifies `default_account_id`, and leaves
    # `pot + Σ accounts == 0` against an untouched purpose ledger.
    it "refuses to delete the main account and changes nothing", :aggregate_failures do
      ally = create(:pool, :account, user: user, name: "Ally")
      income = create(:category, :income, user: user, name: "Salary")
      create(:entry, item: create(:item, category: income), amount: 3_000, date: Date.current)
      create(:account_movement, from_pool: checking, to_pool: ally, amount: 500, date: Date.current)

      expect { delete bank_account_path(checking) }.not_to change(AccountMovement, :count)

      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq("This is your main account — everything flows through it")
      expect(user.reload.default_account).to eq(checking)
      expect([checking.reload.balance, ally.reload.balance]).to eq([2_500, 500])
    end

    # THE OTHER DIRECTION ON THE SAME FIXTURE: the account that is not main deletes, and the money it
    # held returns to the pot rather than vanishing — which is the sentence Home's confirm promises.
    #
    # ** AND THE FLASH NOW CARRIES THE FIGURE, MEASURED (fix round round 2 — item 4). ** It read
    # "Ally deleted." for every account whatever happened to the money; the pot's own difference is
    # what the notice states, and the example above is its other half — an account funded by its own
    # OPENING returns nothing, because that entry and its transfer cancelled on main.
    it "deletes a non-main account and returns what it held to the pot", :aggregate_failures do
      ally = create(:pool, :account, user: user, name: "Ally")
      income = create(:category, :income, user: user, name: "Salary")
      create(:entry, item: create(:item, category: income), amount: 3_000, date: Date.current)
      create(:account_movement, from_pool: checking, to_pool: ally, amount: 500, date: Date.current)

      delete bank_account_path(ally)

      expect(flash[:notice]).to eq("Ally deleted — $500.00 is back in checking.")
      expect(user.pools.find_by(name: "Ally")).to be_nil
      expect(checking.reload.balance).to eq(3_000)
    end
  end
end
