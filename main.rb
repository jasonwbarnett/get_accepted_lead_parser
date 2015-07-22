#!/usr/bin/env ruby
PWD = File.expand_path(File.dirname(__FILE__))
$:.unshift(PWD)

require 'google_oauth2'
require 'oj'
require 'logger'
require 'yaml'
require 'gmail'
require 'closeio'
require 'active_support/all'
# Gmail gem: https://github.com/gmailgem/gmail
# Google Spreadsheets gem: https://github.com/gimite/google-drive-ruby
# Close.io API docs: http://developer.close.io/#Leads
# close.io ruby gem: https://github.com/taylorbrooks/closeio
# Gmail advanced search: https://support.google.com/mail/answer/7190?hl=en

# Goal:
#   - Read and parse emails
#   - Create new tasks in close.io via API with data parsed from emails

@logger = Logger.new(STDOUT)
@logger.level = Logger::DEBUG

def gen_new_lead_template
  new_lead = {}

  #new_lead['display_name'] = 'BlankNameError'
  new_lead['status_id'] = 'stat_3h8Vm5jpZ72TZckGPAil86UKEhKE17SmsgcGOngTgNm'
  new_lead['custom']    = {'Owner'=>'Brad L Lide', 'Lead Source'=>'WEB Inbound - TPR'}
  new_lead['status_label'] = 'New'
  new_lead['contacts'] = []

  new_lead
end

def fetch_closeio_api_key
  if File.exists?(CONFIG_FILE)
    config = YAML.load_file(CONFIG_FILE)
  else
    @logger.error("\"#{CONFIG_FILE}\" Configuration does not exist, exiting...")
    exit 1
  end

  config['closeio_api']
end

def check_deps
  if CLOSEIO_API.nil?
    @logger.error("Missing the close.io API Key \"#{CONFIG_FILE}\" configuration, exiting...")
    exit 2
  end
end

CONFIG_FILE = File.expand_path('~/.getaccepted.yml')
CLOSEIO_API = fetch_closeio_api_key

def main
  check_deps
  options = parse_opts(ARGV)
  @logger.debug("#main :: options: #{options}")

  authorization = get_auth(options.email)
  @logger.debug(authorization)

  gmail = Google::Apis::GmailV1::GmailService.new
  gmail.authorization = authorization

  some_time_ago = 1.day.ago
  begin
    messages = gmail.list_user_messages(options.email, q: "in:inbox subject:'New Lead from The Princeton Review Get Accepted' newer:#{some_time_ago.strftime('%Y%m%d')}")
    message_id =  messages.messages.first.id
    message = gmail.get_user_message(options.email, message_id) if !message_id.nil?

    # Specifics
    email_body = message.payload.body.data
    date       = message.payload.headers.find { |x| x.name == 'Date' }.value.to_time
    message_id = message.payload.headers.find { |x| x.name == 'Message-ID' }.value

    @logger.debug(email_body)
    @logger.debug(date)
    @logger.debug(message_id)

  rescue Google::Apis::ClientError => e
    @logger.debug(e.message)
  end
end

lead_emails.map! do |email|
  if email.message.date.to_time < some_time_ago
    nil
  else

  email_body = email.message.body.to_s
  attr = email.message.body.to_s.split('<br />').map { |x| x.strip }.reject { |x| x.empty? }[1..-1]
  attr = attr.inject({}) do |memo,x|
    x = x.split(':').map { |x| x.strip }
    memo[x[0]] = x[1]
    memo
  end

  attr['email_body'] = email_body.gsub(%r{<br />}, "\n").encode('UTF-8', 'binary', invalid: :replace, undef: :replace, replace: '')
  attr['date'] = email.message.date.to_time
  attr['message_id'] = email.message.message_id
  attr
  end
end

lead_emails.compact!

## Testing:
#last_lead_emails = []
#last_lead_emails << lead_emails.last
#lead_emails = last_lead_emails

#total_attr = []
#lead_emails.each do |email|
#  total_attr << email.keys
#end
#total_attr.flatten!
#total_attr.uniq!
#puts total_attr.join(', ')

## #Goals
## => Have a contact name
## => Have a contact number (if possible)
## => Have a contact email (if possible)
## => Lead Source = Inbound TPR

client = Closeio::Client.new(CLOSEIO_API)

lead_emails.each do |email|
  new_lead = gen_new_lead_template

  new_lead['custom']['Student First Name'] = email['StudentFirstName'].to_s if email.has_key?('StudentFirstName')
  new_lead['custom']['Student Last Name']  = email['StudentLastName'].to_s  if email.has_key?('StudentLastName')

  if email.has_key?('Phone1Number') or email.has_key?('Email')
    contact = {'emails'=>[],'phones'=>[]}
    contact['name'] = "#{email['FirstName'].to_s} #{email['LastName'].to_s}"

    phone1 = email.has_key?('Phone1Number') ? {"phone" => email['Phone1Number'], "type" => (email['Phone1Type'] ? email['Phone1Type'] : "office")} : nil
    email1 = email.has_key?('Email')        ? {"email" => email['Email'],        "type" => "office"} : nil

    contact['emails'] << email1 if email1
    contact['phones'] << phone1 if phone1

    if email1 or phone1
      new_lead['contacts'] << contact
    end
  end
  @logger.debug(email['date'])
  @logger.debug(new_lead)

  created_lead = client.create_lead(Oj.dump(new_lead))

  new_note = {"lead_id" => created_lead['id'], "note" => email['email_body']}
  client.create_note(Oj.dump(new_note))
end
