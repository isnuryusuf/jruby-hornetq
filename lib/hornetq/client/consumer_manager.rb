module HornetQ::Client
  class ConsumerManager
    # config should be a hash of address names of a form such as:
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

    def initialize(factory, session_config, config)
      @session_manager = SessionManager.new(factory, session_config)
      @config = config
    end

    def each(address, queue, &block)
      puts "addresses=#{@config.inspect}"

      address_config = @config[address]
      raise "Unknown address: #{address}" unless address_config
      queue_config = address_config[:queues][queue]
      raise "Unknown queue #{queue}" unless queue_config
      @session_manager.session do |session|
        consumer = session.create_consumer(queue)
        begin
          while msg = consumer.receive do
            # TODO: change based on configs
            if address_config[:serialize] == 'json'
              obj = JSON::Parser.new(msg.body).parse
            elsif address_config[:serialize] == 'ruby_marshal'
              obj = Marshal.load(msg.body)
            elsif address_config[:serialize] == 'string'
              obj = msg.body
            else
              raise "Unknown serialize method #{address_config[:serialize]} for address #{address}"
            end

            yield obj
            msg.acknowledge
          end
        rescue Java::org.hornetq.api.core.HornetQException => e
          raise unless e.cause.code == Java::org.hornetq.api.core.HornetQException::OBJECT_CLOSED
        end
      end
    end

    def close
      @session_manager.close
    end
  end
end
