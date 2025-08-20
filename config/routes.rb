Rails.application.routes.draw do
  get "dashboard/index"
  get "upload" => "dashboard#upload"
  namespace :api do
    namespace :v1 do
      get "anomaly_detections/index"
      get "anomaly_detections/show"
      get "anomaly_detections/update"
      get "anomaly_detections/resolve"
      resources :transactions do
        collection do
          patch :bulk_update
          post :import_csv
          post 'import', to: 'transactions#import_csv'  # Alias for frontend
          get :anomalies
        end
      end
      resources :categories
      resources :rules
      resources :anomaly_detections, only: [:index, :show, :update] do
        member do
          patch :resolve
        end
      end
      # Dashboard API endpoints with caching
      get 'dashboard/statistics', to: 'dashboard#statistics'
      get 'dashboard/recent_transactions', to: 'dashboard#recent_transactions'
      get 'dashboard/active_anomalies', to: 'dashboard#active_anomalies'
      
      # Performance monitoring endpoints
      get 'performance/health', to: 'performance#health'
      get 'performance/metrics', to: 'performance#metrics'
      get 'performance/database_stats', to: 'performance#database_stats'
      get 'performance/cache_stats', to: 'performance#cache_stats'
    end
  end
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  root "dashboard#index"
end
