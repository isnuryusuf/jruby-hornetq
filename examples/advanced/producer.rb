#
# HornetQ Producer:
#          Write messages to the queue
#

# Allow examples to be run in-place without requiring a gem install
$LOAD_PATH.unshift File.dirname(__FILE__) + '/../../lib'

require 'rubygems'
require 'yaml'
require 'hornetq'

count = (ARGV[0] || 1).to_i
config = YAML.load_file(File.dirname(__FILE__) + '/hornetq.yml')['development']

# Create a HornetQ session
HornetQ::Client::Factory.session(config) do |session|
  producer = session.create_producer('TestAddress')
  start_time = Time.now

  puts "Sending messages"
  (1..count).each do |i|
    message = session.create_message(HornetQ::Client::Message::TEXT_TYPE,false)
    # Set the message body text
    message.body = "#{Time.now}: ### Hello, World ###"
    # Send message to the queue
    producer.send(message)
    #puts message
    puts "#{i}\n" if i%1000 == 0
    puts "Durable" if message.durable
  end

  duration = Time.now - start_time
  puts "Delivered #{count} messages in #{duration} seconds at #{count/duration} messages per second"
end