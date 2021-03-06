require 'net/http'
require 'json'
require 'clockwork'
require 'slack-notifier'
include Clockwork

puts "STARTING BUILD LIGHT MONITOR"
circle_token = ENV['CIRCLE_TOKEN']
circle_url = "https://circleci.com/api/v1/organization/secondrotation?circle-token=#{circle_token}&shallow=true&offset=0&limit=30" # CIRCLE CI BUILD STATUS
hue_token = ENV['HUE_TOKEN']
hue_user = 'obbappuser'
hue_url="https://www.meethue.com/api/sendmessage?token=#{hue_token}"
website_url = "https://buildbreaker.herokuapp.com/breaker"
greenCommand="{\"clipCommand\":{\"url\":\"/api/#{hue_user}/groups/0/action\",\"method\":\"PUT\",\"body\":{\"on\":true,\"bri\":255,\"sat\":255,\"hue\":25500}}}"
greenFlashCommand="{\"clipCommand\":{\"url\":\"/api/#{hue_user}/groups/0/action\",\"method\":\"PUT\",\"body\":{\"on\":true,\"bri\":255,\"sat\":255,\"hue\":25500, \"alert\":\"lselect\"}}}"
yellowCommand="{\"clipCommand\":{\"url\":\"/api/#{hue_user}/groups/0/action\",\"method\":\"PUT\",\"body\":{\"on\":true,\"bri\":255,\"sat\":255,\"hue\":12750}}}"
blueCommand="{\"clipCommand\":{\"url\":\"/api/#{hue_user}/groups/0/action\",\"method\":\"PUT\",\"body\":{\"on\":true,\"bri\":255,\"sat\":255,\"hue\":46920}}}"
redCommand="{\"clipCommand\":{\"url\":\"/api/#{hue_user}/groups/0/action\",\"method\":\"PUT\",\"body\":{\"on\":true,\"bri\":255,\"sat\":255,\"hue\":0 }}}"
redFlashCommand="{\"clipCommand\":{\"url\":\"/api/#{hue_user}/groups/0/action\",\"method\":\"PUT\",\"body\":{\"on\":true,\"bri\":255,\"sat\":255,\"hue\":0, \"alert\":\"lselect\"}}}"
offCommand="{\"clipCommand\":{\"url\":\"/api/#{hue_user}/groups/0/action\",\"method\":\"PUT\",\"body\":{\"on\":false,\"bri\":255,\"sat\":255,\"hue\":25500}}}"
beerCommand="{\"clipCommand\":{\"url\":\"/api/obbappuser/groups/0/action\",\"method\":\"PUT\",\"body\":{\"on\":true,\"bri\":255,\"sat\":255,\"hue\":15000, \"alert\":\"lselect\"}}}"

command = nil
qotd = JSON.parse(`curl http://api.theysaidso.com/qod`)

notifier = Slack::Notifier.new ENV['SLACK_WEBHOOK_URL']
note = {
  text: qotd['contents']['quotes'][0]['quote'],
  color: 'good'
}
notifier.ping "Quote of the day, by: #{qotd['contents']['quotes'][0]['author']}", attachments: [note] if notifier

every(15.seconds, 'Checking builds'){
  do_exit = false
  build_status_map = {}
  build_info_map = {}
  resp = Net::HTTP.get_response(URI.parse(circle_url))
  resp_text = resp.body
  #puts resp_text
  recent_builds = JSON.parse(resp_text)
  recent_builds.reverse_each do |build|
    reponame = build['reponame']
    branch = build['branch']
    status = build['status']
    committer = build['committer_name']
    stopped_at = build['stop_time']
    #puts "#{reponame} #{branch} #{status}"
    key = "#{reponame}:#{branch}"
    #puts key
    build_status_map[key] = status
    build_info_map[key] = {committer: committer, committer_date: Time.parse(build['committer_date'])} if build['committer_date']
  end

  build_status_map.each do |key,status|
    if status == 'fixed' || status == 'success' || status == 'no_tests' || status == 'canceled' || status == 'not_run'
      v = build_info_map[key]
      result = `curl -H "Content-Type: application/json" -X PUT -d '{"name":"#{v[:committer]}","fixed_at":"#{v[:committer_date]}","key":"#{key}","token":"helloGazelleWorld"}' #{website_url}` if v.present? && v[:committer_date]
    elsif status == 'failed'
      v = build_info_map[key]
      `curl -H "Content-Type: application/json" -X POST -d '{"name":"#{v[:committer]}","broken_at":"#{v[:committer_date]}","key":"#{key}","token":"helloGazelleWorld"}' #{website_url}` if v.present?
    end
  end

  puts build_status_map

  if Time.now.hour >= 2 && Time.now.hour <=10 
    command_to_issue = offCommand
    do_exit = true
  elsif Time.now.wday == 4 && Time.now.hour == 20 && Time.now.strftime("%M") == "00"
    command_to_issue = beerCommand
  elsif recent_builds[0]['status'] == 'failed'
    command_to_issue = redFlashCommand
  elsif build_status_map.has_value?('failed')
    command_to_issue = redCommand
  elsif build_status_map.has_value?('running')
    command_to_issue = blueCommand
  else
    command_to_issue = greenCommand
  end

  puts "Issuing command #{command_to_issue}"
  res = Net::HTTP.post_form(URI.parse(hue_url), 'clipmessage' => command_to_issue)
  puts res.body
 

  if do_exit
    Signal.trap 'TERM' do
      puts 'Unicorn master intercepting TERM and sending myself QUIT instead'
      Process.kill 'QUIT', Process.pid
    end

    defined?(ActiveRecord::Base) and ActiveRecord::Base.connection.disconnect!
    exit
  end  
}