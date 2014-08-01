class Tools
  def self.seed_db(r) #Update all of the database, adding new entries if needed. Should be run once an hour.
    connection = r.connect(:host => RDB_CONFIG[:host], :port => RDB_CONFIG[:port])
    client = Octokit::Client.new(:client_id => KEYS[:client_id], :client_secret => KEYS[:client_secret])
    per_page = 100
    response = client.search_repos("library language:Rust", per_page: per_page)
    pages = (response.total_count/per_page).ceil
    (1..pages).map do |i|
      unless i == 1
        response = client.search_repos("library language:Rust", per_page: per_page, page: i)
      end
      for repo in response.items
        unless repo.fork
          puts "Working on #{repo.full_name}"
          begin
            readme = Base64.encode64(Octokit.readme(repo.full_name, :accept => 'application/vnd.github.V3.raw'))
          rescue Octokit::NotFound
            puts "Couldn't find a README for #{repo.full_name}"
          rescue Octokit::TooManyRequests
            puts "Getting rate limited for #{repo.full_name}"
          end
          r.db(RDB_CONFIG[:db]).table("libraries").insert({
            :id             => repo.id,
            :name           => repo.name,
            :full_name      => repo.full_name,
            :star_gazers    => repo.stargazers_count,
            :forks          => repo.forks,
            :description    => repo.description,
            :last_updated   => repo.updated_at,
            :content        => readme,
            :tags           => []
          }).run(connection)
        end
      end
    end
  end
end
