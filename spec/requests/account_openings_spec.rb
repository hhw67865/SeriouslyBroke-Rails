# frozen_string_literal: true

require "rails_helper"

# ** THE WIRE CONTRACT FOR SAYING WHAT AN ACCOUNT HOLDS (account-openings spec §§3-4). ** The
# arithmetic is `spec/services/account_opening_spec.rb`'s subject; what is pinned here is the door:
# who may open it, which verb does what, and the status a refusal comes back with.
#
# ** IT REPLACES TWO FILES, and their examples are named where each one's successor is. **
# `spec/requests/account_fundings_spec.rb` (onboarding step 2 — one movement from main per account)
# and `spec/requests/opening_balances_spec.rb` (step 3 — the one-time main correction) are DELETED
# with their controllers:
#
#   * "moves the entered balance from main to the account" → "writes the record" below, which asserts
#     the entry the funding movement never had beside the movement itself.
#   * "refuses funding main from itself" → there is no such shape: an account is opened, not funded
#     FROM anywhere, and main's own opening is one entry with no movement at all.
#   * "refuses to fund an account a second time" and "refuses a second correction" → both were the
#     one-shot latches, and §2 replaces them outright: a second save is a CORRECTION and is the
#     point. "rewrites the record rather than adding to it" is the successor of the pair.
#   * "refuses a zero amount and keeps it on the card" → zero is a legal answer now ("this account
#     holds nothing"), pinned in the service spec; what is refused instead is a NEGATIVE off main.
#   * the opening-balance file's balance examples (main set to the typed figure, the sign both ways,
#     the entry's date) → the service spec's own, where the formulas are.
RSpec.describe "AccountOpenings", type: :request do
  let(:user) { create(:user) }
  let!(:checking) { create(:pool, :account, user: user, name: "Checking") }
  let(:ally) { create(:pool, :account, user: user, name: "Ally") }

  before do
    user.update!(default_account: checking)
    sign_in user, scope: :user
  end

  def opening_entry_for(account) = Entry.find_by(opening_account_id: account.id)

  it "writes the record for an account that has not answered yet", :aggregate_failures do
    post bank_account_opening_path(ally), params: { account_opening: { balance: "1200.50" } }

    entry = opening_entry_for(ally)
    expect(response).to redirect_to(root_path)
    expect(ally.reload.opened_on).to eq(user.today)
    expect(entry.amount).to eq(1200.50)
    expect(entry.account_movements.sole.to_pool).to eq(ally)
    expect(AccountLedger.new(user).balance_of(ally)).to eq(1200.50)
  end

  # PATCH IS THE CORRECTION and it is the SAME act — one record per account, rewritten. The old
  # doors refused a second submission; this one is built for it.
  it "rewrites the record rather than adding to it", :aggregate_failures do
    post bank_account_opening_path(ally), params: { account_opening: { balance: "500" } }
    original = opening_entry_for(ally)

    patch bank_account_opening_path(ally), params: { account_opening: { balance: "650" } }

    expect(response).to redirect_to(root_path)
    expect(Entry.where.not(opening_account_id: nil).count).to eq(1)
    expect(opening_entry_for(ally).id).to eq(original.id)
    expect(AccountLedger.new(user).balance_of(ally)).to eq(650)
  end

  # OWNERSHIP IS THE SCOPE, as at every other door in this app: `current_user.pools.accounts.find`
  # answers a stranger's id with a 404 rather than with a permission sentence that confirms the row
  # exists.
  it "answers a stranger's account with a 404", :aggregate_failures do
    foreign = create(:pool, :account, user: create(:user))

    post bank_account_opening_path(foreign), params: { account_opening: { balance: "10" } }

    expect(response).to have_http_status(:not_found)
    expect(foreign.reload.opened_on).to be_nil
  end

  # ** A MIRROR CANNOT BE OVERDRAWN BY CONSTRUCTION (§4), and the 422 keeps the typed figure on the
  # row it was typed into. ** `min="0"` on the input is the browser's half of this;
  # `config.browser_validations` is off app-wide and a bare POST bypasses the browser entirely, so
  # the server is the half that counts.
  it "refuses a negative balance on a non-main account", :aggregate_failures do
    post bank_account_opening_path(ally), params: { account_opening: { balance: "-50" } }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("can&#39;t be negative")
    expect(response.body).to include('value="-50"')
    expect(ally.reload.opened_on).to be_nil
  end

  # AN OVERDRAWN CHECKING ACCOUNT IS A FACT (§4), so main takes the figure the mirror cannot.
  it "accepts a negative balance on main", :aggregate_failures do
    post bank_account_opening_path(checking), params: { account_opening: { balance: "-50" } }

    expect(response).to redirect_to(root_path)
    expect(AccountLedger.new(user).balance_of(checking)).to eq(-50)
    expect(opening_entry_for(checking).item.category.name).to eq(Category::OPENING_SHORTFALL_NAME)
  end

  # HTML5 `type="number"` CANNOT BE TRUSTED ALONE — a comma-formatted figure, a blank submit or a
  # crafted POST all reach the server, and none of them may raise.
  it "refuses a figure it cannot read", :aggregate_failures do
    post bank_account_opening_path(checking), params: { account_opening: { balance: "one thousand" } }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("must be a number")
    expect(checking.reload.opened_on).to be_nil
  end
end
