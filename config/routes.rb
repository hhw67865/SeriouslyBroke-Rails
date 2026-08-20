# frozen_string_literal: true

Rails.application.routes.draw do
  # Authentication routes
  devise_for :users, controllers: { registrations: "users/registrations" }

  # Application routes (protected by authentication)
  authenticated :user do
    root "home#index", as: :authenticated_root
  end

  # The former dashboard: still the backward-looking view, no longer the front door.
  get "reports", to: "dashboard#index", as: :reports

  # WHERE BANK ACCOUNTS ARE CREATED — from Home, where accounts render. Plural `bank_accounts`
  # because `resource :account` below is already the user-settings page. Create-only: rename and
  # delete stay on the pool's own edit screen, which already handles every pool type.
  resources :bank_accounts, only: [:create]

  # ONBOARDING STEP 2 (main-account spec §5): giving a fresh account its real balance, as one
  # movement from main. Create-only, same shape as `bank_accounts` above and for the same
  # reason — there is one door and it is on Home, where the card lives.
  resources :account_fundings, only: [:create]

  # ONBOARDING STEP 3 (main-account spec §5): the one-time correction that sets MAIN to its real
  # bank number. Singular — there is at most one of these a user ever writes, the same reason
  # `resource :account` above is singular — and create-only for the same reason as the two routes
  # above it: one door, on Home, where the card lives.
  resource :opening_balance, only: [:create]

  resources :pools do
    member do
      get :categories, to: "pools/categories#index"
      patch :categories, to: "pools/categories#update"
    end
  end
  # THE §6 IMPACT CARD'S FRAGMENT. The envelope on the entry form is DERIVED from the category, so
  # the card has to follow the category select, and the whole of the card — the honest
  # no-envelope shape, the goal shape, whether a period end date exists at all — is a server
  # decision. A collection GET returning the partial keeps it one, rather than shipping
  # `_impact.html.erb` a second time in JavaScript.
  resources :entries, except: [:show] do
    collection do
      get :impact
    end
  end
  resources :items, only: [:edit, :update, :destroy]
  resources :categories do
    resources :items, only: [:index, :new, :create], controller: "categories/items" do
      collection do
        get :merge
        post :merge, action: :perform_merge
        post :move
      end
    end
    member do
      patch :toggle_tracked
    end
    collection do
      patch :update_tracked
    end
  end
  resources :budgets, only: [:new, :create, :edit, :update, :destroy]

  # The rules page (spec §8): every funding rule, grouped by the pool it fills. Named
  # `budget_page` rather than taking the bare `budget` name — `budget_path` is already the member
  # route of `resources :budgets` above, and Rails refuses a duplicate route name outright.
  get "budget" => "budget_page#show", as: :budget_page

  # WHERE THE USER DECLARES THEIR PERIOD AND THEIR INCOME (spec §3, §8). The first and only
  # writer for `typical_income`, `period_cadence` and `period_anchor_date` anywhere in the app —
  # until this route the whole periods system ran on seed data, and §9's structural check was
  # permanently false in production because nothing could ever set the income it reads.
  #
  # ON THE BUDGET PAGE'S CONTROLLER rather than on a users/settings one, because the declaration
  # is not a profile setting: it is the denominator of every figure the Budget page prints, it is
  # edited in place inside the structural check block, and a failed save has to re-render THAT
  # page with its errors. A separate controller would have to rebuild this page's presenter to
  # show a validation message.
  patch "budget/user" => "budget_page#update", as: :budget_page_user

  # WHERE FUNDING PRIORITY IS SET (spec §8). Until this route `pools.priority` was seed data with
  # no writer in the app at all, while every distribution spent by it: `Pool.by_priority` is the
  # fill order AllocationCalculator#fill and Home's waterfall both read.
  #
  # ONE ACCOUNT'S ENVELOPES IN THEIR NEW ORDER, as `pool_ids[]`, because priority is only ever
  # compared within an account — the fill is per-account, so a cross-account ordering is a number
  # nothing reads. Pool.apply_fill_order owns the refusal and the write.
  patch "budget/reorder" => "budget_page#reorder", as: :budget_page_reorder

  # THE SACRIFICE VIEW (spec §9): what would have to give for these rules to fit this income.
  #
  # Reachable only from the two structural-check buttons — the Budget page's and Home's standing
  # band — and it refuses in the two states neither of them can be in: nothing declared, or the
  # budget already fits (see SacrificesController#show). Both refusals redirect to /budget with a
  # sentence rather than 404, because the route is not wrong, the moment is.
  #
  # Singular and verbless: there is no Sacrifice record and nothing on the page is written.
  get "sacrifice" => "sacrifices#show"

  # Splitting a paycheck into envelopes (spec §5). `new` proposes the split — a GET that renders
  # the period as if its distribution had not happened, which it does by DELETING this period's
  # allocation and sweep rows inside a transaction it rolls back, so it takes write locks despite
  # being safe by HTTP's definition (every link to it carries `data-turbo-prefetch="false"`).
  # `create` CONFIRMS it, and is the only request in this app that moves money between pools: it
  # locks the account, replaces any previous split for the period, and writes the movements.
  resources :distributions, only: [:new, :create]

  # Moving money between two envelopes in one account (spec §5). `new` states the damage, `create`
  # writes the single `transfer` movement. Both take `to_pool_id`, `from_pool_id` and `amount` as
  # flat params rather than a nested `pool_movement[…]` hash, because ONE form serves both: the GET
  # recomputes the damage against the ledger and a submitter inside it POSTs the same fields.
  resources :pool_movements, only: [:new, :create]

  resource :account, only: [:show] do
    patch :toggle_theme
    patch :toggle_ming_mode
  end

  # Calendar
  get "calendar", to: "calendar#index", as: :calendar
  get "calendar/week", to: "calendar#week", as: :calendar_week

  # Landing page for non-authenticated users
  root "pages#home"

  # Health check
  get "up" => "rails/health#show", as: :rails_health_check
end
