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

def get_lead_emails(email)
  authorization = get_auth(email)
  @logger.debug(authorization)

  gmail = Google::Apis::GmailV1::GmailService.new
  gmail.authorization = authorization

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
ARGV = ["-u", "brad@get-accepted.com", "-x"]
options = parse_opts(ARGV)
@logger.debug("#main :: options: #{options}")
lead_emails = get_lead_emails(options.email)
