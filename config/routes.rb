Rails.application.routes.draw do

  # Authentication routes
  devise_for :users

  # Application routes (protected by authentication)
  authenticated :user do
    root 'dashboard#index', as: :authenticated_root
    resources :savings_pools do
      member do
        get :categories, to: 'savings_pools/categories#index'
        patch :categories, to: 'savings_pools/categories#update'
      end
    end
    resources :entries
    resources :items, only: [:edit, :update, :destroy]
    resources :categories
    resources :budgets, only: [:new, :create, :edit, :update, :destroy]
  end

  # Landing page for non-authenticated users
  root 'pages#home'

  # Health check
  get "up" => "rails/health#show", as: :rails_health_check
end
