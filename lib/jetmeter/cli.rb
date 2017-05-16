module Jetmeter
  class CLI
    CREDENTIAL_PATH = File.expand_path('~/.jetmeter')

    def initialize(config_path)
      @config = eval(File.read(config_path))
      authenticate_user
      if !access_token_stored?
        save_access_token(retrieve access_token)
      end
    end

    def run
      events_loader = Jetmeter::RepositoryIssueEventsLoader.new(@config)

      reducer = Jetmeter::FlowReducer.new(events_loader)
      accumulators = [
        Jetmeter::LabelAccumulator.new(events_loader, @config),
        Jetmeter::LabelAccumulator.new(events_loader, @config, additive: false),
        Jetmeter::CloseAccumulator.new(@config)
      ]

      reducer = reducer.reduce_all(@config.flows.keys, accumulators)
      File.open(@config.output_path, 'wb') do |file|
        Jetmeter::CsvFormatter.new(reducer.flows).save(file)
      end

      puts "Created CSV: #{@config.output_path}"
    end

    private

    def authenticate_user
      if access_token_stored? && access_token_readable?
        @config.github_credentials = { access_token: File.read(CREDENTIAL_PATH) }
      else
        login, password = ask_credentials
        @config.github_credentials = { login: login, password: password }

        authorization = create_authorization
        save_access_token(authorization.token)
      end
    end

    def ask_credentials
      puts "Your github login:"
      login = STDIN.gets.chomp

      puts "Your github password:"
      password = STDIN.noecho(&:gets).chomp

      [login, password]
    end

    def create_authorization
      auth_note = "jetmeter for #{ENV['USER']}@#{ENV['HOSTNAME']}}"
      @config.client.create_authorization(
        scopes: [:repo],
        note: auth_note
      )
    rescue Octokit::OneTimePasswordRequired
      puts 'Enter 2-factor authentication token:'
      two_factor_token = STDIN.gets.chomp

      @config.client.create_authorization(
        scopes: [:repo],
        note: auth_note,
        headers: { 'X-GitHub-OTP' => two_factor_token }
      )
    end

    def save_access_token(token)
      File.write(CREDENTIAL_PATH, token)
      @config.github_credentials = { access_token: token }
    end

    def access_token_stored?
      File.exist?(CREDENTIAL_PATH)
    end

    def access_token_readable?
      File.readable?(CREDENTIAL_PATH)
    end

    def access_token_writable?
      File.writable?(CREDENTIAL_PATH)
    end
  end
end
