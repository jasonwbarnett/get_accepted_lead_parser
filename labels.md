## Check if label exists?

    list_labels_response = gmail.list_user_labels(email)
    labels = list_labels_response.labels
    labels.select { |x| x.type == "user" }

## Create if it does not exist

    new_label = Google::Apis::GmailV1::Label.new
    new_label.label_list_visibility = "labelShow"
    new_label.message_list_visibility = "show"
    new_label.name = "IMPORTED BY SCRIPT"

    gmail.create_user_label(email, new_label)

## Apply label to message

    modify_message_request = Google::Apis::GmailV1::ModifyMessageRequest.new
    modify_message_request.add_label_ids = []
    modify_message(options.email, gmail_message.id, modify_message_request)
