require 'sinatra/base'

module ForestAdminSinatra
  module Extensions
    module SinatraExtension
      def self.registered(app)
        ForestAdminAgent::Builder::AgentFactory.instance.setup(ForestAdminSinatra.config)
        app.before do
          @request_payload = request.params
          @request_payload = @request_payload.merge(JSON.parse(request.body.read)) if request.body.rewind

          if (request_origin = request.env['HTTP_ORIGIN'])
            headers_list = {
              'Access-Control-Allow-Origin' => request_origin.match(/\A.*\.forestadmin\.com\z/),
              'Access-Control-Allow-Methods' => %i[get post options put delete],
              'Access-Control-Allow-Headers' => %w[* Content-Type Accept AUTHORIZATION Cache-Control],
              'Access-Control-Allow-Credentials' => 'true',
              'Access-Control-Max-Age' => '84600',
              'Access-Control-Expose-Headers' => %w[Cache-Control Content-Language Content-Type Expires Last-Modified]
            }

            app.options '*' do
              if request.env['HTTP_ACCESS_CONTROL_REQUEST_PRIVATE_NETWORK'] == 'true'
                headers_list['Access-Control-Allow-Private-Network'] = 'true'
              end
              if request.env['HTTP_ACCESS_CONTROL_REQUEST_HEADERS']
                headers_list['Access-Control-Allow-Headers'] = env['HTTP_ACCESS_CONTROL_REQUEST_HEADERS']
              end
            end

            headers headers_list
          end
        end

        routes = ForestAdminAgent::Http::Router.routes
        routes.each do |route_name, route_definition|
          uri = if route_name == 'forest'
                  "#{route_definition[:uri]}forest"
                else
                  "/forest#{route_definition[:uri]}"
                end

          app.send(route_definition[:method].downcase.to_sym, uri) do
            raw_path = request.env['PATH_INFO'].split('/')
            uri.split('/').each_with_index do |uri_part, index|
              @request_payload[uri_part.sub(':', '')] = raw_path[index] if uri_part.start_with?(':')
            end
            result = route_definition[:closure].call({ params: @request_payload, headers: request.env })

            [
              result[:status] || result[:content][:status] || 200,
              { 'Content-Type' => 'application/json' },
              [result[:content].to_json]
            ]
          end

          puts "Registering #{route_name} at: #{uri}"
        end
      end
    end
  end
end

Sinatra::Base.register ForestAdminSinatra::Extensions::SinatraExtension
