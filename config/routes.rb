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

  # SETTING MONEY ASIDE, TAKING IT BACK, TOPPING UP, REDUCING AND SKIPPING — one table and one
  # route for all five (computed-claims spec §3.3). An adjustment is a dated, signed delta on ONE
  # rule's accrual, so `create` writes a row and `destroy` deletes one and that is the whole of the
  # resource — the same argument `suggestion_dismissals` above makes for being a resource rather
  # than five verbs on `budget_page`.
  #
  # `rule_id`, `amount` and `date` arrive FLAT rather than nested under `adjustment[...]`, because
  # one form on the rule row serves every one of the five doors and the button pressed is what
  # decides the sign (`amount_sign`) or asks the server for the figure (`skip`). Nesting would name
  # a record the user never says the word for — the UI says set aside, take back, top up, reduce
  # and skip, and never "adjustment".
  #
  # Both actions come back to /budget, the only screen either is reachable from.
  resources :adjustments, only: [:create, :destroy]

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

  # WHERE THE GIVE-WAY ORDER IS SET (spec §8). Until this route `priority` was seed data with no
  # writer in the app at all, while every figure on the Budget page was ranked by it.
  #
  # IT IS A GIVE-WAY ORDER NOW, NOT A FILL ORDER, and that is the substance rather than the
  # vocabulary. Nothing hands money out any more — a category's money is a CLAIM computed from its
  # rules (`ClaimCalculator`/`ClaimLedger`), and every claim is stated in full whether or not the
  # money exists. So priority no longer decides who gets filled first; it decides WHO GIVES WAY
  # when the claims outrun the money, which is the order the shortfall walks in reverse.
  #
  # ONE LIST FOR THE WHOLE USER, because `Category.in_fill_order` ranks every holder against every
  # other. There is no account to compare priority within — that was the pool era's shape, and it
  # is gone with it.
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

  # ── THE PURPOSE LEDGER'S TWO ROUTES ARE GONE (computed-claims spec §§5-6). `resources
  # :distributions` split a paycheck into envelopes and `resources :allocations` moved money
  # between them by hand; both wrote `allocations` rows, and both are deleted whole along with
  # `DistributionsController`, `AllocationsController`, `DistributionPresenter`,
  # `ReallocationPresenter`, `AllocationCalculator`, `AllocationCommitter`, `Waterfall`, their
  # helpers and every view under `app/views/distributions/` and `app/views/allocations/`.
  #
  # THERE IS NOTHING LEFT FOR THEM TO DO. A category's money is a CLAIM computed from its rules
  # (`ClaimCalculator`/`ClaimLedger`), not a balance built by moving money into it, so there is no
  # split to propose, no split to confirm and no envelope to move a dollar out of. What the user
  # used to express by distributing they now express by EDITING THE RULES on /budget, and what
  # they used to express by reallocating they express with an adjustment (`resources :adjustments`
  # above) against the one rule they mean.
  #
  # DO NOT POINT ANYTHING AT `/allocations/new`. Home's fix buttons and the pool era's
  # `resources :pool_movements` both did, and neither route exists; /budget is the door now.
  # The `allocations` TABLE and the physical lane are a separate question, handled with the
  # models — `account_movements` (income routing, account funding) was never reachable here.

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
