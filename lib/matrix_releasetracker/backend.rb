module MatrixReleasetracker
  class Backend
    RateLimit = Struct.new('RateLimit', :backend, :name, :requests, :remaining, :resets_at, :resets_in) do
      def near_limit
        remaining <= requests * 0.05
      end

      def used
        requests - remaining
      end

      def to_s
        "#{backend.name}/#{name}: Used #{used}/#{requests} (#{(used / requests) * 100}%), resets in #{resets_in.to_i} seconds"
      end
    end

    def initialize(config, client)
      @config = config
      @m_client = client

      post_load
    end

    def rate_limit; end

    def rate_limits
      [rate_limit].compact
    end

    def name
      self.class.name.split(':').last
    end

    def users
      @users ||= database[:tracking].where(type: 'user', backend: db_type).map do |t|
        Structs::User.new t.merge(backend: self)
      end

      # @repos = tracking.where(type: 'repo').map do |t|
      #   Structs::Repo.new t[:object], t[:room_id], t[:backend], t[:last_update], t[:extradata]
      # end
    end

    def add_user(name, **data)
      tracking = database[:tracking]
      u = tracking.insert(type: 'user', backend: db_type, object: name, **data)
      @users = nil

      u
    end

    def update_user(name, **data)
      u = find_tracking(name, type: 'user').update(**data)
      @users = nil

      u
    end

    def remove_user(name)
      find_tracking(name, type: 'user').delete
      @users = nil
    end


    def last_releases(_user)
      raise NotImplementedException
    end

    protected

    attr_reader :config, :m_client

    def database
      config[:database]
    end

    def logger
      Logging.logger[self]
    end

    def db_type
      name.downcase
    end

    def post_load; end

    # def post_update
    #   # Cache ephemeral data between starts
    #   Dir.mkdir ephemeral_storage unless Dir.exist? ephemeral_storage
    #   File.write(File.join(ephemeral_storage, 'ephemeral_repos.yml'), @ephemeral_repos.to_yaml)
    #   File.write(File.join(ephemeral_storage, 'ephemeral_users.yml'), @ephemeral_users.to_yaml)
    # end

    def with_stagger(value)
      value + (Random.rand - 0.5) * (value / 2.0)
    end

    def find_repository(name, **filters)
      database[:repositories].where(filters.merge(slug: name, backend: db_type))
    end

    def find_tracking(name, **filters)
      raise 'Using old :type param' if filters[:type] == 'repository'
      database[:tracking].where(filters.merge(object: name, backend: db_type))
    end

    def find_releases(**filters)
      database[:releases].where(filters)
    end
  end
end
