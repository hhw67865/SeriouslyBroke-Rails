Rails.application.routes.draw do
  # Authentication routes
  devise_for :users

  # Application routes (protected by authentication)
  authenticated :user do
    root 'dashboard#index', as: :authenticated_root
  end

  # Landing page for non-authenticated users
  root 'pages#home'

  # Health check
  get "up" => "rails/health#show", as: :rails_health_check
end
