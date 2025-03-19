Rails.application.routes.draw do
  # Authentication routes
  devise_for :users, path: '', path_names: {
    sign_in: 'login',
    sign_out: 'logout',
    sign_up: 'register'
  }

  # Application routes
  authenticate :user do
    root 'dashboard#index'
    
    resources :categories do
      resources :expenses, shallow: true
    end
    
    resources :income_sources do
      resources :paychecks, shallow: true
      resources :upgrades, shallow: true
    end
    
    resources :asset_types do
      resources :assets, shallow: true do
        resources :asset_transactions, shallow: true
      end
    end

    resources :budget_statuses, only: [:create]
  end

  # Health check
  get "up" => "rails/health#show", as: :rails_health_check
end
