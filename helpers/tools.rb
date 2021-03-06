class Tools
  def self.get_tags
    YAML::load(File.open('helpers/yml/tags.yml'))
  end

  def self.seed_db(r) #Update all of the database, adding new entries if needed. Should be run once an hour.
    connection = r.connect(:host => RDB_CONFIG[:host], :port => RDB_CONFIG[:port])
    client = Octokit::Client.new(:client_id => KEYS[:client_id], :client_secret => KEYS[:client_secret])
    per_page = 100.0
    response = client.search_repos("library language:Rust", per_page: per_page)
    pages = (response.total_count/per_page).ceil

    repo_tags = self.get_tags

    add_to_db = lambda do |repo|
      puts "Crunching #{repo.full_name}..."
      unless repo.fork
        tags = []

        repo_tags.each do |tag, repo_names|
          repo_names.each do |repo_name|
            tags << tag if repo_name.downcase == repo.full_name.downcase
          end
        end

        tags = tags.uniq

        begin
          readme = Base64.encode64(client.readme(repo.full_name, :accept => 'application/vnd.github.V3.raw'))
        rescue Octokit::NotFound
          puts "Couldn't find a README for #{repo.full_name}"
        rescue Octokit::TooManyRequests
          puts "Getting rate limited for #{repo.full_name}"
        end
        libraries = r.db(RDB_CONFIG[:db]).table("libraries")
        existing = libraries.get(repo.id.to_i).run(connection)
        days_since_update = (DateTime.now.to_date - repo.pushed_at.to_date).to_i
        if !existing && days_since_update < 183 #Less than 6 months old
          libraries.insert({
            id:                  repo.id,
            name:                repo.name,
            full_name:           repo.full_name,
            stargazers_count:    repo.stargazers_count,
            forks:               repo.forks,
            description:         repo.description,
            last_updated:        repo.pushed_at,
            content:             readme,
            clone_url:           repo.clone_url,
            tags:                tags
          }).run(connection)
        elsif days_since_update < 183
          libraries.get(repo.id.to_i).update({
            name:                repo.name             || existing[:name],
            full_name:           repo.full_name        || existing[:full_name],
            stargazers_count:    repo.stargazers_count || existing[:stargazers_count],
            forks:               repo.forks            || existing[:forks],
            description:         repo.description      || existing[:description],
            last_updated:        repo.pushed_at       || existing[:pushed_at],
            content:             readme                || existing[:readme],
            clone_url:           repo.clone_url        || existing[:clone_url],
            tags:                tags
          }).run(connection)
        end
      end
    end

    (1..pages).map do |i|
      unless i == 1
        response = client.search_repos("library language:Rust", per_page: per_page, page: i)
      end
      for repo in response.items
        add_to_db.call(repo)
      end
    end

    repo_tags.each do |tag, repo_names|
      repo_names.each do |repo_name|
        begin
          add_to_db.call(client.repository(repo_name))
        rescue Octokit::NotFound
          puts "Could not find #{repo_name}"
        end
      end
    end


    connection.close()
  end
end

