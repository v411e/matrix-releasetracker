require 'psych'

module MatrixReleasetracker
  class Config
    def self.load!(filename = 'releasetracker.yml')
      config = Config.new filename
      config.load!
      config
    end

    attr_accessor :filename
    attr_reader :backends, :client, :media, :database

    def load!
      raise 'Config file is missing' unless File.exist? filename

      data = Psych.load File.read(filename)

      @client = [data.fetch(:client, {})].map do |config|
        MatrixReleasetracker::Client.new config
      end.first

      @backends = Hash[data.fetch(:backends, []).map do |config|
        next unless config.key? :type
        type = config.delete(:type).to_s.downcase.to_sym

        backend = MatrixReleasetracker::Backends.constants.find { |c| c.to_s.downcase.to_sym == type }
        next if backend.nil?

        [type, MatrixReleasetracker::Backends.const_get(backend).new(config, @client)]
      end]

      @database = [data.fetch(:database, {})].map do |config|
        Sequel.connect(config[:connection_string])
      end.first || Sequel.connect('sqlite://database.db')

      @database.create_table?(:meta) do
        string :key, primary_key: true
        string :value
      end

      @database[:meta]

      @database.create_table?(:media) do
        string :original_url, primary_key: true
        string :mxc_url
        string :etags, null: true
        string :sha256, null: true
        dattime :timestamp
      end

      @database.create_table?(:releases) do
        string :namespace 
        string :version
        primary_key %i[namespace version]

        string :name
        string :version_name
        string :commit_sha
        datetime :publish_date
        string :release_notes
        string :repo_url
        string :release_url
        string :avatar_url
        string :release_type
      end

      @media = client.media
      @media ||= client.data.delete(:media) { nil }
      @media ||= data.fetch(:media)

      (@media || {}).each do |orig, mxc|
        @database[:media].insert(original_url: orig, mxc_url: mxc, timestamp: Time.now)
      end

      @media = @database[:media]

      true
    end

    def save!
      client.media = @media
      client.save! if client

      File.write(
        filename,
        Psych.dump(
          backends: backends.map { |k, v| v.instance_variable_get(:@config).merge(type: k) },
          client: {
            hs_url: client.api.homeserver.to_s,
            access_token: client.api.access_token,
            device_id: client.api.device_id,
            validate_certificate: client.api.validate_certificate,
            transaction_id: client.api.instance_variable_get(:@transaction_id),
            backoff_time: client.api.instance_variable_get(:@backoff_time)
          },

          database: @database.nil? ? {} : {
            connection_string: @database.url
          }
        )
      )
    end

    private

    def initialize(filename)
      @filename = filename

      @backends = {}
    end
  end
end
