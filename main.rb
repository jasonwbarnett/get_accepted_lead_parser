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

config_file = File.expand_path("~/.getaccepted.yml")

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
some_time_ago = 24.hours.ago.strftime("%Y%m%d")
lead_emails = gmail.inbox.search(gm: "subject:'New Lead from The Princeton Review Get Accepted' newer:#{some_time_ago}")

lead_emails.each do |email|
  attr = email.message.body.to_s.split("<br />").map { |x| x.strip }.reject { |x| x.empty? }[1..-1]
  attr = attr.inject({}) do |memo,x|
    x = x.split(':').map { |x| x.strip }
    memo[x[0]] = x[1]
    memo
  end
end

## #Goals
## => Have a contact name
## => Have a contact number (if possible)
## => Have a contact email (if possible)
## => Lead Source = Inbound TPR

client = Closeio::Client.new(CLOSEIO_API)
