class Google::Apis::GmailV1::Message
  def body
    self.payload.body.data
  end

  def grasshoper_body
    self.payload.parts.first.parts.first.body.data
  end

  def date
    self.payload.headers.find { |x| x.name == 'Date' }.value.to_time
  end

  def message_id
    self.payload.headers.find { |x| x.name == 'Message-ID' }.value
  end
end
