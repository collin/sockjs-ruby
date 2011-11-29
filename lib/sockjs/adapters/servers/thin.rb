# encoding: utf-8

require "forwardable"

require_relative "./rack"

require "rack/chunked"

module SockJS
  module Thin
    class Request < Rack::Request
      # We need to access the async.callback.
      attr_reader :env
    end


    # This is just to make Rack happy.
    # For explanation how does it work check
    # http://macournoyer.com/blog/2009/06/04/pusher-and-async-with-thin
    DUMMY_RESPONSE ||= [-1, Hash.new, Array.new]


    class Response < Response
      extend Forwardable

      attr_reader :body
      def initialize(request, status = nil, headers = Hash.new, &block)
        @request, @body   = request, DelayedResponseBody.new
        @status, @headers = status, headers

        block.call(self) if block
      end

      def async?
        true
      end

      def write_head(status = nil, headers = nil)
        super(status, headers) do
          callback = @request.env["async.callback"]

          app = lambda { |_| [@status, @headers, @body] }
          middleware = ::Rack::Chunked.new(app)
          status, headers, body = middleware.call(@request.env)

          callback.call([status, headers, body])
        end
      end

      def_delegator :body, :write
      def_delegator :body, :finish
    end


    class DelayedResponseBody
      TERM ||= "\r\n"
      TAIL ||= "0#{TERM}#{TERM}"

      # rack chunked can't work, it's sync
      # we have to inherit DelayedResponseBody from it or what
      include EventMachine::Deferrable

      def call(body)
        STDERR.puts("~ body#call #{body.inspect}")
        body.each do |chunk|
          self.write(chunk)
        end
      end

      def write(chunk)
        STDERR.puts("~ body#write #{chunk.inspect}")
        @body_callback.call(chunk)
      end

      def each(&block)
        STDERR.puts("~ body#each #{block.inspect}")
        @body_callback = block
      end

      alias_method :finish, :succeed
    end
  end
end