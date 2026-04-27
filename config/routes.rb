Acta::Web::Engine.routes.draw do
  resources :events, only: %i[index show]
  root to: "events#index"
end
