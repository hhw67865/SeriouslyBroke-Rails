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

  resources :pools do
    member do
      get :categories, to: "pools/categories#index"
      patch :categories, to: "pools/categories#update"
    end
  end
  resources :entries, except: [:show]
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
