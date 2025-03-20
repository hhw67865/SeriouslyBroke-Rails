Rails.application.routes.draw do
  # Authentication routes
  devise_for :users

  # Application routes
  root 'dashboard#index'

  # Health check
  get "up" => "rails/health#show", as: :rails_health_check
end
