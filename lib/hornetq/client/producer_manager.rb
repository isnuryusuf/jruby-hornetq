module HornetQ::Client
  class ProducerManager
    # Config should be a hash of address names of a form such as:
    #  address1:
    #    :serialize: ruby_marshal
    #    :unique:    true
    #    :durable:   true
    #    :queues:
    #      queue1_1:
    #        :durable:  false
    #      queue1_2:
    #  address2:
    #    :serialize: json
    #    :unique:    false
    #    :durable:   false
    #    :queues:
    #      queue2_1:
    #      queue2_2:
    def initialize(session_pool, config, create_queues=false)
      @session_pool = session_pool
      @config = config
      # TODO: Should I keep this for performance for just use send below since it's less hackish?
      config.each do |address,address_config|
        # TODO: change based on configs
        if address_config[:serialize] == 'json'
          body_serialize = 'obj.to_json'
          msg_type = HornetQ::Client::Message::TEXT_TYPE
        elsif address_config[:serialize] == 'ruby_marshal'
          body_serialize = 'Marshal.dump(obj)'
          msg_type = HornetQ::Client::Message::BYTES_TYPE
        elsif address_config[:serialize] == 'string'
          body_serialize = 'obj.to_s'
          msg_type = HornetQ::Client::Message::TEXT_TYPE
        else
          raise "Unknown serialize method #{address_config[:serialize]} for address #{address}"
        end
        durable = !!address_config[:durable]
        eval <<-EOF
          def self.send_#{address}(obj)
            @session_pool.producer("#{address}") do |session, producer|
              message = session.create_message(#{msg_type}, #{durable})
              message.body = #{body_serialize}
              send_with_retry(producer, message)
            end
          end
        EOF
      end

      if create_queues
        @session_pool.session do |session|
          config.each do |address, address_config|
            queue_config = address_config[:queues]
            if queue_config
              queue_config.each_key do |queue|
                # TODO: Need to figure out the distinction between published messages that are durable and queues that are durable
                session.create_queue_ignore_exists(address, queue, !!queue_config[:durable])
              end
            end
          end
        end
      end
    end

    def send(address, obj)
      address_config = @config[address]
      raise "Invalid address #{address} not found in " unless address_config
      @session_pool.producer(address) do |session, producer|
        if address_config[:serialize] == 'json'
          new_obj = obj.to_json
          msg_type = HornetQ::Client::Message::TEXT_TYPE
        elsif address_config[:serialize] == 'ruby_marshal'
          new_obj = Marshal.dump(obj)
          msg_type = HornetQ::Client::Message::BYTES_TYPE
        elsif address_config[:serialize] == 'string'
          new_obj = obj.to_s
          msg_type = HornetQ::Client::Message::TEXT_TYPE
        else
          raise "Unknown serialize method #{address_config[:serialize]} for address #{address}"
        end
        message = session.create_message(msg_type, !!address_config[:durable])
        message.body = new_obj
        send_with_retry(producer, message)
      end
    end

    #######
    private
    #######

    def send_with_retry(producer, message)
      #message.put_string_property(Java::org.hornetq.api.core.SimpleString.new(HornetQ::Client::Message::HDR_DUPLICATE_DETECTION_ID.to_s), Java::org.hornetq.api.core.SimpleString.new("uniqueid#{i}"))
      begin
        producer.send(message)
      rescue Java::org.hornetq.api.core.HornetQException => e
        puts "Received producer exception: #{e.message} with code=#{e.cause.code}"
        if e.cause.code == Java::org.hornetq.api.core.HornetQException::UNBLOCKED
          puts "Retrying the send"
          retry
        end
      end
    end
  end
end