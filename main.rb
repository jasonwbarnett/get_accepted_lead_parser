#!/usr/bin/env ruby
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

def gen_new_lead_template
  new_lead = {}

  #new_lead['display_name'] = 'BlankNameError'
  new_lead['status_id'] = 'stat_3h8Vm5jpZ72TZckGPAil86UKEhKE17SmsgcGOngTgNm'
  new_lead['custom']    = {'Owner'=>'Brad L Lide', 'Lead Source'=>'WEB Inbound - TPR'}
  new_lead['status_label'] = 'New'
  new_lead['contacts'] = []

  new_lead
end

config_file = File.expand_path('~/.getaccepted.yml')

if File.exists?(config_file)
  config = YAML.load_file(config_file)
else
  $stderr.puts "\"#{config_file}\" Configuration does not exist, exiting..."
  exit 1
end

# Check that a username and password exists.
USERNAME = config['username']
PASSWORD = config['password']
CLOSEIO_API = config['closeio_api']

if USERNAME.nil? or PASSWORD.nil?
  $stderr.puts "Missing either the username or password in the \"#{config_file}\" configuration, exiting..."
  exit 2
end

gmail = Gmail.connect(USERNAME, PASSWORD)
some_time_ago = 100.hours.ago.strftime('%Y%m%d')
lead_emails = gmail.inbox.search(gm: "subject:'New Lead from The Princeton Review Get Accepted' newer:#{some_time_ago}")

lead_emails.map! do |email|
  email_body = email.message.body.to_s
  attr = email.message.body.to_s.split('<br />').map { |x| x.strip }.reject { |x| x.empty? }[1..-1]
  attr = attr.inject({}) do |memo,x|
    x = x.split(':').map { |x| x.strip }
    memo[x[0]] = x[1]
    memo
  end
  attr['email_body'] = email_body.gsub(%r{<br />}, "\n")
  attr
end

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

  new_lead['custom']['Student First Name'] = email['StudentFirstName'] if email.has_key?('StudentFirstName')
  new_lead['custom']['Student Last Name']  = email['StudentLastName']  if email.has_key?('StudentLastName')

  if email.has_key?('Phone1Number') or email.has_key?('Email')
    contact = {'emails'=>[],'phones'=>[]}
    contact['name'] = "#{email['FirstName']} #{email['LastName']}"

    phone1 = email.has_key?('Phone1Number') ? {"phone" => email['Phone1Number'], "type" => (email['Phone1Type'] ? email['Phone1Type'] : "office")} : nil
    email1 = email.has_key?('Email')        ? {"email" => email['Email'],        "type" => "office"} : nil

    contact['emails'] << email1 if email1
    contact['phones'] << phone1 if phone1

    if email1 or phone1
      new_lead['contacts'] << contact
    end
  end

  created_lead = client.create_lead(new_lead)

  new_note = {"lead_id" => created_lead['id'], "note" => email['email_body']}
  client.create_note(new_note)
end
