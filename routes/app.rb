class RustKit < Sinatra::Base
  before do
    Tools::seed_db(settings.r)
  end

  get '/' do
    erb :main
  end

  get '/test-flash' do
    redirect to('/')
    erb :main
  end

end