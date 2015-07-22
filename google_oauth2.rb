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

    opts.on('-e', '--email-address EMAIL',
            'Email address of the user whose inbox you wish to search'
            ) { |v| options.email = v }

    opts.separator ''
    opts.separator 'Common Options:'

    opts.on('-n', '--dry-run',
            'perform a trial run with no changes made'
            ) { options.dry_run = true }

    opts.on('-l', '--label LABEL',
            'Apply gmail label to emails who have been parsed and uploaded to Close.io'
            ) { |v| options.label_name = v }

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
  @logger.info('Searching Gmail, search query: "%s"' % search_query)

  list_messages_response = gmail.list_user_messages(email, q: search_query)
  messages += list_messages_response.messages unless list_messages_response.messages.nil?

  while list_messages_response.next_page_token
    list_messages_response = gmail.list_user_messages(email, q: search_query, page_token: list_messages_response.next_page_token)
    messages += list_messages_response.messages
  end

  @logger.info("Found #{messages.length} emails in Gmail")
  messages
end

def get_lead_emails(gmail, email)
  begin
    messages = get_all_messages(gmail, email)

    @logger.info("Fetching and parsing emails")
    lead_emails = messages.pmap do |msg|
      message_id = msg.id
      @logger.debug("Grabbing message #{message_id} from Gmail.")
      message = gmail.get_user_message(email, message_id)

      email_details = message.body.split('<br />').map { |x| x.strip }.reject { |x| x.empty? }[1..-1]
      email_details = email_details.inject({}) do |memo,x|
        x = x.split(':').map { |x| x.strip }
        memo[x[0]] = x[1]
        memo
      end

      email_details['body'] = message.body.gsub(%r{<br */>}, "\n")
      email_details['date'] = message.date
      email_details['message_id'] = message.message_id

      email_details
    end
    @logger.info("Finished fetching and parsing emails")
  rescue Google::Apis::ClientError => e
    @logger.debug(e.message)
  end

  lead_emails
end

def get_label(gmail, email, name)
  list_labels_response = gmail.list_user_labels(email)
  labels = list_labels_response.labels
  labels.select { |x| x.type == "user" }

  label = labels.find { |x| x.name.strip.downcase == name.strip.downcase }
end

def create_label(gmail, email, name)
  new_label = Google::Apis::GmailV1::Label.new
  new_label.label_list_visibility = "labelShow"
  new_label.message_list_visibility = "show"
  new_label.name = name

  gmail.create_user_label(email, new_label)
end
