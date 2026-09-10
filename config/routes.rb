# frozen_string_literal: true

Rails.application.routes.draw do
  devise_for :users, controllers: { registrations: "users/registrations" }

  authenticated :user do
    root "home#index", as: :authenticated_root
  end

  get "reports", to: "dashboard#index", as: :reports

  resources :accounts, only: [:create, :edit, :update, :destroy]

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

  resources :rules, only: [:new, :create, :edit, :update, :destroy] do
    collection do
      match :preview, via: [:post, :patch]
    end
  end

  get "budget" => "budget_page#show", as: :budget_page
  patch "budget/user" => "budget_page#update", as: :budget_page_user
  patch "budget/reorder" => "budget_page#reorder", as: :budget_page_reorder
  resources :adjustments, only: [:create, :destroy]
  get "sacrifice" => "sacrifices#show"

  resource :settings, only: [:show] do
    patch :toggle_theme
    patch :toggle_ming_mode
  end

  get "calendar", to: "calendar#index", as: :calendar
  get "calendar/week", to: "calendar#week", as: :calendar_week

  root "pages#home"
  get "up" => "rails/health#show", as: :rails_health_check
end
