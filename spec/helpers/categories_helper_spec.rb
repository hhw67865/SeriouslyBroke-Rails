# frozen_string_literal: true

require "rails_helper"

RSpec.describe CategoriesHelper, type: :helper do
  describe "#budget_status" do
    it "returns 'Budget exceeded' when percentage is 111 or above", :aggregate_failures do
      expect(helper.budget_status(111)).to eq("Budget exceeded")
      expect(helper.budget_status(150)).to eq("Budget exceeded")
    end

    it "returns 'Over budget' when percentage is between 101 and 110", :aggregate_failures do
      expect(helper.budget_status(101)).to eq("Over budget")
      expect(helper.budget_status(105)).to eq("Over budget")
      expect(helper.budget_status(110)).to eq("Over budget")
    end

    it "returns 'On track' when percentage is 100 or below", :aggregate_failures do
      expect(helper.budget_status(100)).to eq("On track")
      expect(helper.budget_status(75)).to eq("On track")
      expect(helper.budget_status(25)).to eq("On track")
      expect(helper.budget_status(0)).to eq("On track")
    end
  end

  describe "#budget_status_color" do
    it "returns 'bg-status-danger' when percentage is 111 or above", :aggregate_failures do
      expect(helper.budget_status_color(111)).to eq("bg-status-danger")
      expect(helper.budget_status_color(150)).to eq("bg-status-danger")
    end

    it "returns 'bg-status-warning' when percentage is between 101 and 110", :aggregate_failures do
      expect(helper.budget_status_color(101)).to eq("bg-status-warning")
      expect(helper.budget_status_color(105)).to eq("bg-status-warning")
      expect(helper.budget_status_color(110)).to eq("bg-status-warning")
    end

    it "returns 'bg-brand' when percentage is 100 or below", :aggregate_failures do
      expect(helper.budget_status_color(100)).to eq("bg-brand")
      expect(helper.budget_status_color(75)).to eq("bg-brand")
      expect(helper.budget_status_color(25)).to eq("bg-brand")
      expect(helper.budget_status_color(0)).to eq("bg-brand")
    end
  end
end
