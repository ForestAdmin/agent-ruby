require 'spec_helper'
require 'action_controller'
require 'action_dispatch'
require 'forest_admin_agent'
require 'openid_connect'

require_relative '../../../app/controllers/forest_admin_rails/forest_controller'

module ForestAdminRails
  describe ForestController do
    let(:controller) { described_class.new }
    let(:logger) { instance_double(Logger, log: nil) }
    # rubocop:disable RSpec/VerifiedDoubles
    # Using regular double for response mock as ActionController::Response is complex and changes dynamically
    let(:response_mock) { double('response', status: nil, 'status=': nil, body: nil, headers: {}) }
    # rubocop:enable RSpec/VerifiedDoubles

    before do
      allow(ForestAdminAgent::Facades::Container).to receive(:logger).and_return(logger)
      allow(ForestAdminAgent::Facades::Container).to receive(:cache).with(:is_production).and_return(false)
      allow(ForestAdminAgent::Facades::Container).to receive(:cache).with(:customize_error_message).and_return(nil)
      allow(controller).to receive(:response).and_return(response_mock)
      allow(controller).to receive(:render) do |options|
        allow(response_mock).to receive_messages(body: options[:json].to_json, status: options[:status])
      end
    end

    describe '#exception_handler' do
      context 'when exception is AuthenticationOpenIdClient' do
        it 'returns OpenID error format with real exception' do
          exception = ForestAdminAgent::Http::Exceptions::AuthenticationOpenIdClient.new('Auth failed')
          # Define response as singleton method for this instance
          exception.define_singleton_method(:response) { 'Invalid token' }

          controller.send(:exception_handler, exception)

          expect(response_mock.status).to eq(401)
          json = JSON.parse(response_mock.body)
          expect(json['error']).to eq('Auth failed')
          expect(json['error_description']).to eq('Invalid token')
          expect(json['state']).to eq(401)
        end

        it 'returns OpenID error format with double when testing response attribute' do
          # rubocop:disable RSpec/VerifiedDoubles
          exception = double(
            'AuthenticationOpenIdClient',
            message: 'Auth failed',
            response: 'Token expired',
            status: 401
          )
          # rubocop:enable RSpec/VerifiedDoubles
          allow(exception).to receive(:try).with(:status).and_return(401)
          allow(exception).to receive(:try).with(:data).and_return(nil)
          allow(exception).to receive(:full_message).and_return('Full error trace')

          # Make the case/when work by stubbing the === method
          allow(ForestAdminAgent::Http::Exceptions::AuthenticationOpenIdClient).to receive(:===).with(exception).and_return(true)
          allow(OpenIDConnect::Exception).to receive(:===).with(exception).and_return(false)

          controller.send(:exception_handler, exception)

          expect(response_mock.status).to eq(401)
          json = JSON.parse(response_mock.body)
          expect(json['error']).to eq('Auth failed')
          expect(json['error_description']).to eq('Token expired')
          expect(json['state']).to eq(401)
        end
      end

      context 'when exception is OpenIDConnect::Exception' do
        it 'returns OpenID error format' do
          # rubocop:disable RSpec/VerifiedDoubles
          exception = double(
            'OpenIDConnect::Exception',
            message: 'OpenID error',
            response: 'Token expired',
            status: 403
          )
          # rubocop:enable RSpec/VerifiedDoubles
          allow(exception).to receive(:try).with(:status).and_return(403)
          allow(exception).to receive(:try).with(:data).and_return(nil)
          allow(exception).to receive(:full_message).and_return('Full error trace')

          # Make the case/when work by stubbing the === method
          allow(ForestAdminAgent::Http::Exceptions::AuthenticationOpenIdClient).to receive(:===).with(exception).and_return(false)
          allow(OpenIDConnect::Exception).to receive(:===).with(exception).and_return(true)

          controller.send(:exception_handler, exception)

          expect(response_mock.status).to eq(403)
          json = JSON.parse(response_mock.body)
          expect(json['error']).to eq('OpenID error')
          expect(json['error_description']).to eq('Token expired')
          expect(json['state']).to eq(403)
        end
      end

      context 'with ValidationError' do
        it 'returns errors format with validation error details' do
          exception = ForestAdminAgent::Http::Exceptions::ValidationError.new('Email is invalid')
          # Mock get_error_message to work with real HttpException instances
          # Note: get_error_message has a bug where it checks error.ancestors instead of error.class.ancestors
          allow(controller).to receive(:get_error_message).with(exception).and_return('Email is invalid')

          controller.send(:exception_handler, exception)

          expect(response_mock.status).to eq(400)
          json = JSON.parse(response_mock.body)
          expect(json['errors']).to be_an(Array)
          expect(json['errors'].length).to eq(1)
          expect(json['errors'][0]['name']).to eq('ValidationError')
          expect(json['errors'][0]['detail']).to eq('Email is invalid')
          expect(json['errors'][0]['status']).to eq(400)
          expect(json['errors'][0]['data']).to be_nil
        end

        it 'calls get_error_message' do
          exception = ForestAdminAgent::Http::Exceptions::ValidationError.new('Invalid input')
          allow(controller).to receive(:get_error_message).and_return('Invalid input')

          controller.send(:exception_handler, exception)

          expect(controller).to have_received(:get_error_message).with(exception)
        end

        it 'supports custom name' do
          exception = ForestAdminAgent::Http::Exceptions::ValidationError.new('Invalid data', 'CustomValidationError')
          allow(controller).to receive(:get_error_message).and_return('Invalid data')

          controller.send(:exception_handler, exception)

          json = JSON.parse(response_mock.body)
          expect(json['errors'][0]['name']).to eq('CustomValidationError')
        end
      end

      context 'with ForbiddenError' do
        it 'returns errors format with 403 status' do
          exception = ForestAdminAgent::Http::Exceptions::ForbiddenError.new('Access denied')
          allow(controller).to receive(:get_error_message).with(exception).and_return('Access denied')

          controller.send(:exception_handler, exception)

          expect(response_mock.status).to eq(403)
          json = JSON.parse(response_mock.body)
          expect(json['errors'][0]['name']).to eq('ForbiddenError')
          expect(json['errors'][0]['detail']).to eq('Access denied')
          expect(json['errors'][0]['status']).to eq(403)
        end
      end

      context 'with NotFoundError' do
        it 'returns errors format with 404 status' do
          exception = ForestAdminAgent::Http::Exceptions::NotFoundError.new('Resource not found')
          allow(controller).to receive(:get_error_message).with(exception).and_return('Resource not found')

          controller.send(:exception_handler, exception)

          expect(response_mock.status).to eq(404)
          json = JSON.parse(response_mock.body)
          expect(json['errors'][0]['name']).to eq('NotFoundError')
          expect(json['errors'][0]['detail']).to eq('Resource not found')
          expect(json['errors'][0]['status']).to eq(404)
        end
      end

      context 'with custom HttpException' do
        it 'returns errors format with custom status and name' do
          exception = ForestAdminAgent::Http::Exceptions::HttpException.new(418, 'I am a teapot', 'TeapotError')
          allow(controller).to receive(:get_error_message).with(exception).and_return('I am a teapot')

          controller.send(:exception_handler, exception)

          expect(response_mock.status).to eq(418)
          json = JSON.parse(response_mock.body)
          expect(json['errors'][0]['name']).to eq('TeapotError')
          expect(json['errors'][0]['detail']).to eq('I am a teapot')
          expect(json['errors'][0]['status']).to eq(418)
        end
      end

      context 'when exception does not have name attribute' do
        it 'uses exception class name as fallback' do
          # rubocop:disable RSpec/VerifiedDoubles
          exception = double(
            'GenericError',
            message: 'Something went wrong',
            respond_to?: false,
            class: StandardError
          )
          # rubocop:enable RSpec/VerifiedDoubles
          allow(exception.class).to receive(:name).and_return('StandardError')
          allow(exception).to receive(:try).with(:status).and_return(nil)
          allow(exception).to receive(:try).with(:data).and_return(nil)
          allow(exception).to receive(:is_a?).with(ForestAdminAgent::Http::Exceptions::AuthenticationOpenIdClient).and_return(false)
          allow(exception).to receive(:is_a?).with(OpenIDConnect::Exception).and_return(false)
          allow(exception).to receive(:full_message).and_return('Full error')
          allow(controller).to receive(:get_error_message).with(exception).and_return('Unexpected error')

          controller.send(:exception_handler, exception)

          json = JSON.parse(response_mock.body)
          expect(json['errors']).to be_an(Array)
          expect(json['errors'][0]['name']).to eq('StandardError')
          expect(json['errors'][0]['detail']).to eq('Unexpected error')
        end
      end

      context 'when exception has no status' do
        it 'returns errors format with 500 status' do
          # rubocop:disable RSpec/VerifiedDoubles
          exception = double(
            'GenericError',
            message: 'Generic error',
            respond_to?: false,
            class: StandardError
          )
          # rubocop:enable RSpec/VerifiedDoubles
          allow(exception.class).to receive(:name).and_return('StandardError')
          allow(exception).to receive(:try).with(:status).and_return(nil)
          allow(exception).to receive(:try).with(:data).and_return(nil)
          allow(exception).to receive(:is_a?).with(ForestAdminAgent::Http::Exceptions::AuthenticationOpenIdClient).and_return(false)
          allow(exception).to receive(:is_a?).with(OpenIDConnect::Exception).and_return(false)
          allow(exception).to receive(:full_message).and_return('Full error')
          allow(controller).to receive(:get_error_message).with(exception).and_return('Unexpected error')

          controller.send(:exception_handler, exception)

          expect(response_mock.status).to eq(500)
          json = JSON.parse(response_mock.body)
          expect(json['errors']).to be_an(Array)
          expect(json['errors'][0]['name']).to eq('StandardError')
          expect(json['errors'][0]['status']).to be_nil
        end
      end

      context 'when exception has no data' do
        it 'returns errors format with nil data' do
          # rubocop:disable RSpec/VerifiedDoubles
          exception = double(
            'GenericError',
            message: 'Generic error',
            respond_to?: false,
            class: StandardError
          )
          # rubocop:enable RSpec/VerifiedDoubles
          allow(exception.class).to receive(:name).and_return('StandardError')
          allow(exception).to receive(:try).with(:status).and_return(nil)
          allow(exception).to receive(:try).with(:data).and_return(nil)
          allow(exception).to receive(:is_a?).with(ForestAdminAgent::Http::Exceptions::AuthenticationOpenIdClient).and_return(false)
          allow(exception).to receive(:is_a?).with(OpenIDConnect::Exception).and_return(false)
          allow(exception).to receive(:full_message).and_return('Full error')
          allow(controller).to receive(:get_error_message).with(exception).and_return('Unexpected error')

          controller.send(:exception_handler, exception)

          json = JSON.parse(response_mock.body)
          expect(json['errors'][0]['data']).to be_nil
        end
      end

      context 'with production and non-production modes' do
        it 'logs exception in non-production mode' do
          # rubocop:disable RSpec/VerifiedDoubles
          exception = double(
            'GenericError',
            message: 'Test error',
            respond_to?: false,
            class: StandardError
          )
          # rubocop:enable RSpec/VerifiedDoubles
          allow(exception.class).to receive(:name).and_return('StandardError')
          allow(exception).to receive(:try).with(:status).and_return(nil)
          allow(exception).to receive(:try).with(:data).and_return(nil)
          allow(exception).to receive(:is_a?).with(ForestAdminAgent::Http::Exceptions::AuthenticationOpenIdClient).and_return(false)
          allow(exception).to receive(:is_a?).with(OpenIDConnect::Exception).and_return(false)
          allow(exception).to receive(:full_message).and_return('Full error trace')
          allow(controller).to receive(:get_error_message).with(exception).and_return('Unexpected error')
          allow(ForestAdminAgent::Facades::Container).to receive(:cache).with(:is_production).and_return(false)

          controller.send(:exception_handler, exception)

          expect(logger).to have_received(:log).with('Debug', 'Full error trace')
        end

        it 'does not log exception in production mode' do
          # rubocop:disable RSpec/VerifiedDoubles
          exception = double(
            'GenericError',
            message: 'Test error',
            respond_to?: false,
            class: StandardError
          )
          # rubocop:enable RSpec/VerifiedDoubles
          allow(exception.class).to receive(:name).and_return('StandardError')
          allow(exception).to receive(:try).with(:status).and_return(nil)
          allow(exception).to receive(:try).with(:data).and_return(nil)
          allow(exception).to receive(:is_a?).with(ForestAdminAgent::Http::Exceptions::AuthenticationOpenIdClient).and_return(false)
          allow(exception).to receive(:is_a?).with(OpenIDConnect::Exception).and_return(false)
          allow(exception).to receive(:full_message).and_return('Full error trace')
          allow(controller).to receive(:get_error_message).with(exception).and_return('Unexpected error')
          allow(ForestAdminAgent::Facades::Container).to receive(:cache).with(:is_production).and_return(true)

          controller.send(:exception_handler, exception)

          expect(logger).not_to have_received(:log)
        end
      end
    end
  end
end
