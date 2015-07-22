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
ARGV = ["-e", "brad@get-accepted.com", "-x"]
options = parse_opts(ARGV)
@logger.debug("#main :: options: #{options}")

authorization = get_auth(options.email)
@logger.debug(authorization)

gmail = Google::Apis::GmailV1::GmailService.new
gmail.authorization = authorization

lead_emails = get_lead_emails(gmail, options.email)
