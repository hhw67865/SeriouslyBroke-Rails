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

  # WHERE BANK ACCOUNTS ARE BORN, RENAMED AND DELETED — from Home, where accounts render. Plural
  # `bank_accounts` because `resource :account` below is already the user-settings page.
  #
  # THE THREE MEMBER ACTIONS ARRIVED FROM `resources :pools` (two-ledger spec §5, Task 7). Rename
  # and delete lived on the pool's own edit screen, which handled all three pool types; two of the
  # three are gone (a budget envelope and a savings goal are CATEGORIES now), so what is left is a
  # screen about accounts, and it belongs on the resource that names them. `index`, `show` and
  # `new` are deliberately absent: Home IS the accounts index and each account's own card is its
  # show, and the create form is the card on Home.
  resources :bank_accounts, only: [:create, :edit, :update, :destroy]

  # ONBOARDING STEP 2 (main-account spec §5): giving a fresh account its real balance, as one
  # movement from main. Create-only, same shape as `bank_accounts` above and for the same
  # reason — there is one door and it is on Home, where the card lives.
  resources :account_fundings, only: [:create]

  # ONBOARDING STEP 3 (main-account spec §5): the one-time correction that sets MAIN to its real
  # bank number. Singular — there is at most one of these a user ever writes, the same reason
  # `resource :account` above is singular — and create-only for the same reason as the two routes
  # above it: one door, on Home, where the card lives.
  resource :opening_balance, only: [:create]

  # ── `resources :pools` IS GONE (two-ledger spec §5, Task 7), and with it `PoolsController`,
  # `Pools::CategoriesController`, every view under `app/views/pools/` and `PoolsHelper`. The
  # index was the savings-goals list (savings are CATEGORIES now and render on /categories), the
  # show page described a pool's balance and history (a category's own page does), the form
  # created envelopes and goals (rules live on /budget, goals on /categories) and the member
  # `categories` pair was the connect/disconnect manager for a link that no longer exists — "the
  # only connection between an account and a category is the movement" (§1).
  #
  # ACCOUNTS KEEP EVERY DOOR THEY HAD: `resources :bank_accounts` above now carries `edit`,
  # `update` and `destroy` alongside `create`.

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

  # PUTTING ONE SUGGESTION DOWN, AND PICKING IT BACK UP (Henry's ruling of 2026-08-20, which
  # reverses §8's no-dismissal design — see app/views/budget_page/_suggestions.html.erb).
  #
  # A RESOURCE OF ITS OWN rather than two more non-RESTful verbs on `budget_page`: a dismissal is
  # a ROW, `create` writes one and `destroy` deletes one, and that is the whole of the resource.
  # Both actions redirect back to /budget, which is the only screen either is reachable from.
  resources :suggestion_dismissals, only: [:create, :destroy]

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

  # WHERE FUNDING PRIORITY IS SET (spec §8). Until this route `priority` was seed data with no
  # writer in the app at all, while every distribution spent by it.
  #
  # EVERY CLAUSE OF THIS COMMENT WAS FALSE FOR ONE COMMIT and is rewritten rather than patched: it
  # described `pool_ids[]`, a per-account ordering and `Pool.apply_fill_order`, and the two-ledger
  # cutover (spec §2) replaced all three. `AllocationCalculator#fill` walks
  # `Category.in_fill_order` over ONE root, so there is no account to compare priority within.
  #
  # THE USER'S RULE-CARRYING HOLDER CATEGORIES IN THEIR NEW ORDER, as `category_ids[]` — one list
  # for the whole page. `Category.apply_fill_order` owns the refusal and the write, and it refuses
  # any list that is not exactly `in_fill_order.with_a_rule`, which is exactly what the page
  # renders a draggable card for.
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

  # Moving money by hand on the PURPOSE LEDGER (spec §5, two-ledger spec §2): `category → category`
  # or `available ↔ category`. `new` states the damage, `create` writes the single `transfer`
  # allocation. Both take `to_category_id`, `from_category_id` and `amount` as flat params rather
  # than a nested hash, because ONE form serves both: the GET recomputes the damage against the
  # ledger and a submitter inside it POSTs the same fields. `"available"` names the root on either
  # side, and it is not a uuid, so it cannot collide with a category id.
  resources :allocations, only: [:new, :create]

  # ── THE POOL-ERA TWIN IS GONE (Task 6). `resources :pool_movements` stood here for one task
  # longer than the route above, because Home's fix buttons were its only remaining links and
  # Home's rows were pools. Home's rows are CATEGORIES now and its buttons point at
  # `/allocations/new`, so the twin — the route, `PoolMovementsController`, `PoolReallocation
  # Presenter`, `PoolMovementsHelper` and `app/views/pool_movements/` — was deleted whole.
  # The TABLE survives as the physical lane (income routing, account funding) under the name it
  # always meant — `account_movements`, since Task 8 — and nothing about that lane was ever
  # reachable through this route.

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
