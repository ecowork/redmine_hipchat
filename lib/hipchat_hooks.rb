# encoding: utf-8

class NotificationHook < Redmine::Hook::Listener

  def controller_issues_new_after_save(context = {})
    issue   = context[:issue]
    project = issue.project
    return true if !hipchat_configured?(project)

    author  = CGI::escapeHTML(User.current.name)
    tracker = CGI::escapeHTML(issue.tracker.name.downcase)
    subject = CGI::escapeHTML(issue.subject)
    url     = get_url(issue)

    assigned_message = issue.assigned_to.nil? ? "NULL" : "#{issue.assigned_to.name}"

    text =   "#{author} 建立 #{tracker} <a href='#{url}'> ##{issue.id} </a> : #{subject}"
    text +=  "狀態:「#{issue.status.name}」. 分派給:「#{assigned_message}」. 意見:「#{truncate(issue.description)}」"


    data          = {}
    data[:text]   = text
    data[:token]  = hipchat_auth_token(project)
    data[:room]   = hipchat_room_name(project)
    data[:notify] = hipchat_notify(project)

    send_message(data)
  end



  def controller_issues_edit_before_save(context = { })
    issue   = context[:issue]
    project = issue.project
    journal = context[:journal]
    editor = journal.user
    tracker = CGI::escapeHTML(issue.tracker.name.downcase)
    assigned_message = issue_assigned_changed?(issue)
    status_message = issue_status_changed?(issue)
    url     = get_url(issue)
    subject = CGI::escapeHTML(issue.subject)

    text = ""
    text += "#{editor.name} 編輯 #{tracker} <a href='#{url}'> ##{issue.id} </a> : #{subject}"
    text += "狀態:「#{status_message}」. 分派給:「#{assigned_message}」. 意見:「#{truncate(journal.notes)}」"

    data          = {}
    data[:text]   = text
    data[:token]  = hipchat_auth_token(project)
    data[:room]   = hipchat_room_name(project)
    data[:notify] = hipchat_notify(project)

    send_message(data)
  end



  def controller_wiki_edit_after_save(context = {})
    page    = context[:page]
    project = page.wiki.project
    return true if !hipchat_configured?(project)

    author       = CGI::escapeHTML(User.current.name)
    wiki         = CGI::escapeHTML(page.pretty_title)
    project_name = CGI::escapeHTML(project.name)
    url          = get_url(page)
    text         = "#{author} edited #{project_name} wiki page <a href='#{url}'>#{wiki}</a>"

    text = ""
    text += "#{author} edited the  <a href='#{url}'>#{wiki}</a> on #{project.name}."

    data          = {}
    data[:text]   = text
    data[:token]  = hipchat_auth_token(project)
    data[:room]   = hipchat_room_name(project)
    data[:notify] = hipchat_notify(project)

    send_message(data)
  end

  private

  def hipchat_configured?(project)
    if !project.hipchat_auth_token.empty? && !project.hipchat_room_name.empty?
      return true
    elsif Setting.plugin_redmine_hipchat[:projects] &&
        Setting.plugin_redmine_hipchat[:projects].include?(project.id.to_s) &&
        Setting.plugin_redmine_hipchat[:auth_token] &&
        Setting.plugin_redmine_hipchat[:room_id]
      return true
    else
      Rails.logger.info "Not sending HipChat message - missing config"
    end
    false
  end

  def hipchat_auth_token(project)
    return project.hipchat_auth_token if !project.hipchat_auth_token.empty?
    return Setting.plugin_redmine_hipchat[:auth_token]
  end

  def hipchat_room_name(project)
    return project.hipchat_room_name if !project.hipchat_room_name.empty?
    return Setting.plugin_redmine_hipchat[:room_id]
  end

  def hipchat_notify(project)
    return project.hipchat_notify if !project.hipchat_auth_token.empty? && !project.hipchat_room_name.empty?
    Setting.plugin_redmine_hipchat[:notify]
  end

  def get_url(object)
    case object
    when Issue    then "#{Setting[:protocol]}://#{Setting[:host_name]}/issues/#{object.id}"
    when WikiPage then "#{Setting[:protocol]}://#{Setting[:host_name]}/projects/#{object.wiki.project.identifier}/wiki/#{object.title}"
    else
      Rails.logger.info "Asked redmine_hipchat for the url of an unsupported object #{object.inspect}"
    end
  end

  def send_message(data)
    Rails.logger.info "Sending message to HipChat: #{data[:text]}"
    req = Net::HTTP::Post.new("/v1/rooms/message")
    req.set_form_data({
                        :auth_token => data[:token],
                        :room_id => data[:room],
                        :notify => data[:notify] ? 1 : 0,
                        :from => 'Redmine',
                        :message => data[:text]
    })
    req["Content-Type"] = 'application/x-www-form-urlencoded'

    http = Net::HTTP.new("api.hipchat.com", 443)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    begin

      http.start do |connection|
        connection.request(req)
      end
    rescue Net::HTTPBadResponse => e
      Rails.logger.error "Error hitting HipChat API: #{e}"
    end
  end

  def truncate(text, length = 20, end_string = '…')
    return unless text
    words = text.split()
    words[0..(length-1)].join(' ') + (words.length > length ? end_string : '')
  end

  def issue_status_changed?(issue)
    if issue.status_id_changed?
      old_status = IssueStatus.find(issue.status_id_was)
      "從 #{old_status.name} 變更為 #{issue.status.name}"
    else
      "#{issue.status.name}"
    end
  end


  def issue_assigned_changed?(issue)
    if issue.assigned_to_id_changed?
      old_assigned_to = User.find(issue.assigned_to_id_was) rescue nil
      old_assigned = old_assigned_to.nil? ? "無" : "#{old_assigned_to.lastname} #{old_assigned_to.firstname}"
      new_assigned = issue.assigned_to.nil? ? "無" : "#{issue.assigned_to.lastname} #{issue.assigned_to.firstname}"
      "從 #{old_assigned} 變更為 #{new_assigned}"
    else
      issue.assigned_to.nil? ? "無" : "#{issue.assigned_to.lastname} #{issue.assigned_to.firstname}"
    end
  end
end
