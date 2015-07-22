#!/usr/bin/env ruby
require 'yaml'
require 'optparse'
require 'ostruct'
require 'logger'
require 'active_support/all'
require 'google/api_client/client_secrets'
require 'google/api_client/auth/installed_app'
require 'google/apis/gmail_v1'

@logger = Logger.new(STDOUT)
@logger.level = Logger::INFO

def parse_opts(args)
  options = OpenStruct.new

  opt_parser = OptionParser.new do |opts|
    opts.banner = "\nUsage: #{File.basename($PROGRAM_NAME)} [options]"

    opts.separator ''
    opts.separator 'Required Options:'

    opts.on('-u', '--user-email EMAIL',
            'Email address of the user whose inbox you wish to search'
            ) { |v| options.email = v }

    opts.separator ''
    opts.separator 'Common Options:'

    opts.on('-n', '--dry-run',
            'perform a trial run with no changes made'
            ) { options.dry_run = true }

    opts.on('-x', '--debug',
            'Enables some helpful debugging output.'
           ) { @logger.level = Logger::DEBUG }

    opts.on('-h', '--help', 'Display this help message.') do
      puts opts
      exit
    end

    opts.separator ''
    opts.separator 'Examples:'
    opts.separator ''
    opts.separator "# Search brad@get-accepted.com inbox"
    opts.separator "#{File.basename($PROGRAM_NAME)} -u 'brad@get-accepted.com'"
    opts.separator ''
  end

  begin
    opt_parser.parse!
    fail(OptionParser::MissingArgument, '-d is a required option.') unless options.email
  rescue OptionParser::MissingArgument, OptionParser::InvalidArgument, OptionParser::InvalidOption => e
    puts "ERROR: " + e.message
    puts opt_parser
    exit 1
  end

  options
end

def authorize_new_user
  #require 'google/api_client/auth/installed_app'
  flow = Google::APIClient::InstalledAppFlow.new(
    client_id: '440182892791-stn3ro59rkopd6mo0jkaeituvqq392aj.apps.googleusercontent.com',
    client_secret: 'Ogn6VFtAs25HZndhnlKqQJXO',
    scope: 'https://mail.google.com/ https://www.googleapis.com/auth/gmail.modify https://www.googleapis.com/auth/gmail.readonly'
  )
  authorization = flow.authorize

  authorization
end

def save_refresh_token(email, token)
  #require 'yaml'

  get_accepted_config = YAML.load_file(File.expand_path("~/.getaccepted.yml"))
  get_accepted_config[email] = {'refresh_token' => token}
  @logger.debug("#save_refresh_token :: get_accepted_config: #{get_accepted_config}")
  File.open(File.expand_path("~/.getaccepted.yml"), 'w') { |f| f.puts get_accepted_config.to_yaml }
end

def grab_user_refresh_token(email)
  #require 'yaml'

  get_accepted_config = YAML.load_file(File.expand_path("~/.getaccepted.yml"))
  @logger.debug("#grab_user_refresh_token :: get_accepted_config: #{get_accepted_config}")

  if get_accepted_config[email]
    get_accepted_config[email]['refresh_token']
  else
    nil
  end
end

def authorize_existing_user(refresh_token)
  #require 'google/api_client/client_secrets'
  client_secrets = Google::APIClient::ClientSecrets.load(File.expand_path("~/client_secret_440182892791-stn3ro59rkopd6mo0jkaeituvqq392aj.apps.googleusercontent.com.json"))
  authorization = client_secrets.to_authorization
  authorization.refresh_token = refresh_token
  authorization.fetch_access_token!

  authorization
end

def get_auth(email)
  if user_refresh_token = grab_user_refresh_token(email)
    new_user = false
    authorization = authorize_existing_user(user_refresh_token)
  else
    new_user = true
    authorization = authorize_new_user
    save_refresh_token(email, authorization.refresh_token)
  end

  authorization
end

def get_all_messages(gmail, email)
  messages = []
  some_time_ago = 1.day.ago.strftime('%Y/%m/%d')

  search_query = "in:inbox subject:'New Lead from The Princeton Review Get Accepted' after:#{some_time_ago}"
  @logger.info('Searching emails in Gmail, search query: "%s"' % search_query)

  list_messages_response = gmail.list_user_messages(email, q: search_query)
  messages += list_messages_response.messages

  while list_messages_response.next_page_token
    list_messages_response = gmail.list_user_messages(email, q: search_query, page_token: list_messages_response.next_page_token)
    messages += list_messages_response.messages
  end

  @logger.info("Finished fetching #{messages.length} emails from Gmail")
  messages
end
