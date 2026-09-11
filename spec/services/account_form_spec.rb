# frozen_string_literal: true

require "rails_helper"

RSpec.describe AccountForm do
  let(:user) { create(:user, :biweekly) }
  let(:emergency) { create(:account, user: user, name: "Emergency", opening_balance: 500) }
  let(:paycheck) { create(:item, :income, user: user, name: "Paycheck") }
  let(:target_rows) do
    {
      "0" => { item_id: "", amount: "200", starts_on: "2026-09-04" },
      "1" => { item_id: paycheck.id, percent: "10", starts_on: "2026-09-04" }
    }
  end

  before { create(:account, user: user, name: "Checking", opening_balance: 1_000) }

  def form(account, params) = described_class.new(account, params)

  it "renames, corrects the balance, sets the mode and writes target rows together", :aggregate_failures do
    saved = form(emergency, name: "Emergency fund", balance: "650", keeps_extra: "0", savings_targets_attributes: target_rows).save

    expect(saved).to be(true)
    emergency.reload
    expect(emergency.name).to eq("Emergency fund")
    expect(emergency.balance).to eq(650)
    expect(emergency).not_to be_keeps_extra
    expect(emergency.savings_targets.map(&:words)).to contain_exactly("$200.00 a period", "10% of Paycheck")
  end

  it "removes a row marked for destruction" do
    target = create(:savings_target, account: emergency)

    form(emergency, { savings_targets_attributes: { "0" => { id: target.id, _destroy: "1" } } }).save

    expect(emergency.savings_targets.reload).to be_empty
  end

  it "writes nothing when a row is refused", :aggregate_failures do
    saved = form(
      emergency,
      {
        name: "Renamed",
        savings_targets_attributes: { "0" => { item_id: paycheck.id, percent: "150", starts_on: "2026-09-04" } }
      }
    ).save

    expect(saved).to be(false)
    expect(emergency.reload.name).to eq("Emergency")
    expect(emergency.errors.full_messages.join).to include("100%")
  end

  it "refuses a balance that is not a number without renaming", :aggregate_failures do
    saved = form(emergency, { name: "Renamed", balance: "abc" }).save

    expect(saved).to be(false)
    expect(emergency.reload.name).to eq("Emergency")
  end
end
