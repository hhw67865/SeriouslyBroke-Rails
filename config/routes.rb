Rails.application.routes.draw do
  # Authentication routes
  devise_for :users

  # Landing page
  root 'pages#home'

  # Application routes (protected by authentication)
  get 'dashboard', to: 'dashboard#index'

  # Health check
  get "up" => "rails/health#show", as: :rails_health_check
end
