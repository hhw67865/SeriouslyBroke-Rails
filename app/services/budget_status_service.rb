# frozen_string_literal: true

class BudgetStatusService
  require 'net/http'
  require 'json'

  def initialize(user, month, year)
    @user = user
    @month = month
    @year = year
    @api_key = ENV['OPENAI_SECRET_KEY']
  end

  def self.call(user, month, year)
    new(user, month, year).call
  end

  def call
    if month == 1
      previous_month = 12
      previous_year = year - 1
    else
      previous_month = month - 1
      previous_year = year
    end

    generate_summary(data_for_prompt)
  end

  private

  attr_reader :user, :month, :year, :api_key

  def data_for_prompt
    previous_month = month == 1 ? 12 : month - 1
    previous_year = month == 1 ? year - 1 : year

    {
      expenses: user.all_expenses(month, year),
      previous_expenses: user.all_expenses(previous_month, previous_year),
      categories: user.categories,
      current_month: month == Date.today.month && year == Date.today.year,
      days_left: (Date.new(year, month, -1) - Date.today).to_i
    }
  end

  def generate_summary(data)
    uri = URI('https://api.openai.com/v1/chat/completions')
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Post.new(uri)
    request['Content-Type'] = 'application/json'
    request['Authorization'] = "Bearer #{api_key}"

    request.body = {
      model: 'gpt-4o',
      messages: [
        { role: 'system', content: 'You are a helpful financial advisor providing concise budget summaries.' },
        { role: 'user', content: create_prompt(data) }
      ],
      temperature: 0.2,
      max_tokens: 350
    }.to_json

    response = http.request(request)
    JSON.parse(response.body).dig('choices', 0, 'message', 'content')
  end

  def create_prompt(data)
    if data[:expenses].count.zero?
      return "No expenses or budgets set. Please add expenses and set category budgets for analysis."
    end

    <<~PROMPT
      Provide a concise budget analysis for #{month} #{year}:

      Here are the categories for this user with their budgets:
      #{data[:categories].map { |c| "- #{c.name}: $#{c.minimum_amount}" }.join("\n")}

      Here are the expenses for the month:
      #{data[:expenses].map { |e| "- #{e.name}: $#{e.amount}. Frequency: #{e.frequency}. Category: #{e.category.name}. date: #{e.date}" }.join("\n")}

      Here are the expenses for the previous month:
      #{data[:previous_expenses].map { |e| "- #{e.name}: $#{e.amount}. Frequency: #{e.frequency}. Category: #{e.category.name}. date: #{e.date}" }.join("\n")}

      Note that annual expenses are prorated each month.

      #{if data[:current_month]
        "Please note that the current month is not yet complete and there are still #{data[:days_left]} days left in the month.
        Also consider that monthly frequencies will only happen once a month, so if a category's budget is close to being spent but the main expense contributing to the category is a monthly expense, it may not be overspent yet.
        Please provide:

        1. Tell the user how much they should be aiming to spend per week in the remaining days of the month to stay on track to meet their budget goals. Please look at the previous month trend on the habits of the user's expenses when analyzing this.
        2. What categories are trending higher than the previous month based on the day.
        3. An analysis of the categories that are at risk of overspending based on the current progress and the expenses that are contributing to the category. Again please consider the monthly frequencies. Please look at the previous month trend when analyzing the risk of overspending.
        4. What expenses should I expect and prepare for in the upcoming days?

        Again please consider the monthly frequencies.
        When providing analysis, please give a direction and talk factual numbers and data."
      else
        "Please provide:

        1. a comparison of the current month's expenses to the previous month's expenses, what categories were higher than the previous month.
        2. What categories went over budget?
        3. What expenses were to cause of either getting over budget or over the previous month."

      end}

      Keep the analysis brief and focused on overspending issues.
      Please keep the word count under 200 words.
      Use markdown formatting for better readability.
    PROMPT
  end
end
