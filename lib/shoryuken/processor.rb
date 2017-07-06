module Shoryuken
  class Processor
    include Util

    attr_reader :queue, :sqs_msg

    def self.process(queue, sqs_msg)
      new(queue, sqs_msg).process
    end

    def initialize(queue, sqs_msg)
      @queue   = queue
      @sqs_msg = sqs_msg
    end

    def process
      return logger.error { "No worker found for #{queue}" } unless worker

      worker.class.server_middleware.invoke(worker, queue, sqs_msg, body) do
        worker.perform(sqs_msg, body)
      end
    rescue Exception => ex
      logger.error { "Processor failed: #{ex.message}" }
      logger.error { ex.backtrace.join("\n") } unless ex.backtrace.nil?

      raise
    end

    private

    def worker
      @_worker ||= Shoryuken.worker_registry.fetch_worker(queue, sqs_msg)
    end

    def worker_class
      worker.class
    end

    def body
      @_body ||= sqs_msg.is_a?(Array) ? sqs_msg.map(&method(:parse_body)) : parse_body(sqs_msg)
    end

    def parse_body(sqs_msg)
      body_parser = worker_class.get_shoryuken_options['body_parser']

      case body_parser
      when :json
        JSON.parse(sqs_msg.body)
      when Proc
        body_parser.call(sqs_msg)
      when :text, nil
        sqs_msg.body
      else
        if body_parser.respond_to?(:parse)
          # JSON.parse
          body_parser.parse(sqs_msg.body)
        elsif body_parser.respond_to?(:load)
          # see https://github.com/phstc/shoryuken/pull/91
          # JSON.load
          body_parser.load(sqs_msg.body)
        end
      end
    end
  end
end
