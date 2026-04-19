# frozen_string_literal: true

Rails.application.routes.draw do
  # Authentication routes
  devise_for :users, controllers: { registrations: "users/registrations" }

  # Application routes (protected by authentication)
  authenticated :user do
    root "dashboard#index", as: :authenticated_root
  end

  resources :savings_pools do
    member do
      get :categories, to: "savings_pools/categories#index"
      patch :categories, to: "savings_pools/categories#update"
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
