#!/usr/bin/env ruby
require 'google/api_client/client_secrets'
require 'google/api_client/auth/installed_app'
require 'google/apis/gmail_v1'
require 'launchy'


client = Google::APIClient.new
flow = Google::APIClient::InstalledAppFlow.new(
  client_id: '440182892791-stn3ro59rkopd6mo0jkaeituvqq392aj.apps.googleusercontent.com',
  client_secret: 'Ogn6VFtAs25HZndhnlKqQJXO',
  scope: 'https://mail.google.com/ https://www.googleapis.com/auth/gmail.modify https://www.googleapis.com/auth/gmail.readonly'
)
authorization = flow.authorize
#client.authorization = flow.authorize

exit

client_secrets = Google::APIClient::ClientSecrets.load(File.expand_path("~/client_secret_440182892791-stn3ro59rkopd6mo0jkaeituvqq392aj.apps.googleusercontent.com.json"))
auth_client = client_secrets.to_authorization
auth_client.update!(
  :scope => 'https://mail.google.com/ https://www.googleapis.com/auth/gmail.modify https://www.googleapis.com/auth/gmail.readonly',
  :redirect_uri => 'urn:ietf:wg:oauth:2.0:oob'
)

auth_uri = auth_client.authorization_uri.to_s
Launchy.open(auth_uri)

print "Paste auth code in browser: "
auth_client.code = gets.chomp
auth_client.fetch_access_token!

gmail = Google::Apis::GmailV1::GmailService.new
gmail.authorization = auth_client

messages = gmail.list_user_messages('brad@get-accepted.com', q: "subject:'New Lead from The Princeton Review Get Accepted'")
msg =  messages.messages.first
msg_data = gmail.get_user_message('jbarnett@mindjet.com', msg.id) if !msg.nil?
