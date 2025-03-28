# frozen_string_literal: true

require "rails_helper"

RSpec.describe CategoriesHelper, type: :helper do
  describe "#budget_status" do
    it "returns 'Budget exceeded' when percentage is over 100" do
      expect(helper.budget_status(105)).to eq("Budget exceeded")
    end

    it "returns 'Almost depleted' when percentage is between 91 and 100" do
      expect(helper.budget_status(95)).to eq("Almost depleted")
    end

    it "returns 'Warning zone' when percentage is between 76 and 90" do
      expect(helper.budget_status(80)).to eq("Warning zone")
    end

    it "returns 'On track' when percentage is between 51 and 75" do
      expect(helper.budget_status(60)).to eq("On track")
    end

    it "returns 'Well under budget' when percentage is 50 or below", :aggregate_failures do
      expect(helper.budget_status(50)).to eq("Well under budget")
      expect(helper.budget_status(25)).to eq("Well under budget")
    end
  end

  describe "#budget_status_color" do
    it "returns 'bg-status-danger' when percentage is over 100" do
      expect(helper.budget_status_color(105)).to eq("bg-status-danger")
    end

    it "returns 'bg-status-danger' when percentage is between 91 and 100" do
      expect(helper.budget_status_color(95)).to eq("bg-status-danger")
    end

    it "returns 'bg-status-warning' when percentage is between 76 and 90" do
      expect(helper.budget_status_color(80)).to eq("bg-status-warning")
    end

    it "returns 'bg-brand' when percentage is 75 or below", :aggregate_failures do
      expect(helper.budget_status_color(75)).to eq("bg-brand")
      expect(helper.budget_status_color(50)).to eq("bg-brand")
    end
  end
end
