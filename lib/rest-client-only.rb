require "securerandom"
require "rest-client"
require "nokogiri"

payload = { username: ENV.fetch("ATREA_USERNAME"), password: ENV.fetch("ATREA_PASSWORD") }
control_url = "https://control.atrea.eu"
php_session_id = nil
body = nil
RestClient.post "#{control_url}?action=login&lng=cs", payload do |response|
  php_session_id = response.cookies["PHPSESSID"]
  body = response.follow_redirection
end
raise "Login failed" unless php_session_id

core = RestClient.get "#{control_url}/core/core.php?action=init&_ts=#{SecureRandom.hex(4)}", { cookies: { PHPSESSID: php_session_id } }
client = Nokogiri::XML(core.body).at_xpath('//client')
user_id = client['id']
user_name = client['name']
puts "User ID: #{user_id}, User Name: #{user_name}"

# core_run = RestClient.post "#{control_url}/core/core.php?Sync=1&action=run&object=app&lng=28&rVer=1&_ts=#{SecureRandom.hex(4)}", { name: "rdUserSet", path: "apps/rdUserSet/" }, { cookies: { PHPSESSID: php_session_id } }
# core_load = RestClient.post "#{control_url}/core/core.php?Sync=1&action=load&object=setting&_ts=#{SecureRandom.hex(4)}", { path: "apps/rdUserSet" }, { cookies: { PHPSESSID: php_session_id } }

core_run_rd5 = RestClient.post "#{control_url}/core/core.php?Sync=1&action=run&object=app&lng=28&rVer=1&_ts=#{SecureRandom.hex(4)}", { name: "rd5Control", path: "apps/rd5Control/" }, { cookies: { PHPSESSID: php_session_id } }
core_load_rd5 = RestClient.post "#{control_url}/core/core.php?Sync=1&action=load&object=setting&_ts=#{SecureRandom.hex(4)}", { path: "apps/rd5Control" }, { cookies: { PHPSESSID: php_session_id } }

#_get_rd5_client = RestClient.get "#{control_url}/_data/sources/rd5/client.php?ver=yTAvZ&_ts=#{SecureRandom.hex(4)}", { cookies: { PHPSESSID: php_session_id } }
#_get_rd5_client28 = RestClient.get "#{control_url}/_data/sources/rd5/client.28.php?ver=yTAvZ&_ts=#{SecureRandom.hex(4)}", { cookies: { PHPSESSID: php_session_id } }
units_table = RestClient.get "#{control_url}/_data/data.php?Sync=1&action=getdata&rH&rE&table=userUnits&ds=rd5&_ts=#{SecureRandom.hex(4)}", { cookies: { PHPSESSID: php_session_id }, "App-name": "rd5Control" }

# Retrieve user units
item = Nokogiri::XML(units_table.body).at_xpath("//i")
user_id = item["_uid"]
unit = item["unit"]
iid = item["id"]
puts "User ID: #{user_id}, Unit ID: #{unit}"

# Retrieve units list with `unit_id` = `ident`
records = RestClient.get "#{control_url}/_data/data.php?Sync=1&action=getrecord&id=#{unit}&table=units&ds=rd5&_ts=#{SecureRandom.hex(4)}", { cookies: { PHPSESSID: php_session_id }, "App-name": "rd5Control" }
# Get the first 'i' node from the first table
unit_id = Nokogiri::XML(records.body).at_xpath('//table/i')['ident']

data = RestClient.get "#{control_url}/apps/rd5Control/handle.php?Sync=1&action=unitQuery&query=loged&user=#{user_id}&unit=#{unit_id}&#{SecureRandom.hex(2)}&_ts=#{SecureRandom.hex(4)}", { cookies: { PHPSESSID: php_session_id }, "App-name": "rd5Control" }
sid = Nokogiri::XML(data.body).at_xpath('//login')['sid']
puts "SID: #{sid}"
if sid != "0"
  puts "Login complete !"
  exit
end
re_login = RestClient.post "#{control_url}/apps/rd5Control/handle.php?action=unitLogin&user=#{user_id}&unit=#{unit_id}&table=userUnits&idPwd=#{iid}&#{SecureRandom.hex(2)}&_ts=#{SecureRandom.hex(4)}", { comm: "config/login.cgi?magic=" }, { cookies: { PHPSESSID: php_session_id }, "App-name": "rd5Control"  }
time = Nokogiri::XML(re_login.body).at_xpath('//sended')["time"].to_i
while sid == "0" do
  data = RestClient.get "#{control_url}/apps/rd5Control/handle.php?Sync=1&action=unitQuery&query=loged&user=#{user_id}&unit=#{unit_id}&#{SecureRandom.hex(2)}&_ts=#{SecureRandom.hex(4)}", { cookies: { PHPSESSID: php_session_id }, "App-name": "rd5Control" }
  sid = Nokogiri::XML(data.body).at_xpath('//login')['sid']
  puts "#{time -= 1} #{data}"
  sleep 1
end
puts "Login complete !"


# nop = RestClient.get "#{control_url}/_data/data.php?action=NOP&_ts=#{SecureRandom.hex(4)}", { cookies: { PHPSESSID: php_session_id } }

# data = RestClient.get "#{control_url}/apps/rd5Control/handle.php?Sync=1&action=unitQuery&query=loged&user=#{user_id}&unit=#{unit_id}&UIT&_ts=#{SecureRandom.hex(4)}", { cookies: { PHPSESSID: php_session_id } }
# data = RestClient.get "#{control_url}/apps/rd5Control/handle.php?Sync=1&action=unitQuery&query=loged&user=#{user_id}&unit=#{unit_id}&#{"ios"}&_ts=#{SecureRandom.hex(4)}", { cookies: { PHPSESSID: php_session_id }, "App-name": "rd5Control" }
#
# curl 'https://control.atrea.eu/'
# core = RestClient.get "#{control_url}/apps/rd5Control/handle.php?Sync=1&action=unitQuery&query=loged&user=#{user_id}&_ts=#{SecureRandom.hex(4)}", { cookies: { PHPSESSID: php_session_id } }
