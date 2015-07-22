#!/usr/bin/env ruby
PWD = File.expand_path(File.dirname(__FILE__))
$:.unshift(PWD)

require 'google_oauth2'
require 'gmailv1'
require 'celluloid/current'
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

Celluloid.logger.level = Logger::WARN
module Enumerable
  # Simple parallel map using Celluloid::Futures
  def pmap(&block)
    futures = map { |elem| Celluloid::Future.new(elem, &block) }
    futures.map(&:value)
  end
end

def gen_new_lead_template
  new_lead = {}

  #new_lead['display_name'] = 'BlankNameError'
  new_lead['status_id'] = 'stat_3h8Vm5jpZ72TZckGPAil86UKEhKE17SmsgcGOngTgNm'
  new_lead['custom']    = {'Owner'=>'Brad L Lide', 'Lead Source'=>'WEB Inbound - TPR'}
  new_lead['contacts']  = []
  new_lead['status_label'] = 'New'

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

######################
## TESTING
######################
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

######################
## CONSTANTS
######################
CONFIG_FILE = File.expand_path('~/.getaccepted.yml')
CLOSEIO_API = fetch_closeio_api_key

######################
## MAIN
######################
check_deps
options = parse_opts(ARGV)
@logger.debug("#main :: options: #{options}")

authorization = get_auth(options.email)
@logger.debug(authorization)

gmail = Google::Apis::GmailV1::GmailService.new
gmail.authorization = authorization

lead_emails = get_lead_emails(gmail, options.email)

if gmail_label = get_label(gmail, options.email, options.label_name)
  @logger.debug("Found label: %s" % gmail_label)
elsif gmail_label = create_label(gmail, options.email, options.label_name)
  @logger.debug("Created label: %s" % gmail_label)
end

closeio = Closeio::Client.new(CLOSEIO_API, false)

lead_emails.pmap do |email|
  threshold = '2015-07-22 13:07:17 -0700'.to_time
  threshold = '2015-07-22 11:51:00 PDT'.to_time
  unless email['date'] > threshold
    @logger.debug("#main :: skipping message #{email['message_id']}")
    next
  end

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
  @logger.debug("Date: %s; Message-ID: %s" % [email['date'], email['message_id']])
  @logger.debug(new_lead)

  ## add label

  created_lead = closeio.create_lead(Oj.dump(new_lead))

  new_note = {"lead_id" => created_lead['id'], "note" => email['body']}
  @logger.debug(new_note)
  closeio.create_note(Oj.dump(new_note))
end
