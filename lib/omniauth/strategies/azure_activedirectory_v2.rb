# frozen_string_literal: true

require 'omniauth-oauth2'

module OmniAuth
  module Strategies
    class AzureActivedirectoryV2 < OmniAuth::Strategies::OAuth2
      BASE_AZURE_URL = 'https://login.microsoftonline.com'

      option :name, 'azure_activedirectory_v2'
      option :tenant_provider, nil

      DEFAULT_SCOPE = 'openid profile email'

      # tenant_provider must return client_id, client_secret and optionally tenant_id and base_azure_url
      args [:tenant_provider]

      def client
        log :debug, "***** OmniAuth::Strategies::AzureActivedirectoryV2#client - Starting"
        log :debug, "***** OmniAuth::Strategies::AzureActivedirectoryV2#client - options are #{options.inspect}"
        provider = if options.tenant_provider
          log :debug, "***** OmniAuth::Strategies::AzureActivedirectoryV2#client - options.tenant_provider is truthy"
          options.tenant_provider.new(self)
        else
          log :debug, "***** OmniAuth::Strategies::AzureActivedirectoryV2#client - options.tenant_provider is falsy"
          options
        end
        log :debug, "***** OmniAuth::Strategies::AzureActivedirectoryV2#client - provider is #{provider.inspect}"

        options.client_id = provider.client_id
        log :debug, "***** OmniAuth::Strategies::AzureActivedirectoryV2#client - options.client_id = #{options.client_id}"
        options.client_secret = provider.client_secret
        log :debug, "***** OmniAuth::Strategies::AzureActivedirectoryV2#client - options.client_secret = #{options.client_secret}"
        options.tenant_id =
          provider.respond_to?(:tenant_id) ? provider.tenant_id : 'common'
        log :debug, "***** OmniAuth::Strategies::AzureActivedirectoryV2#client - options.tenant_id = #{options.tenant_id}"
        options.base_azure_url =
          provider.respond_to?(:base_azure_url) ? provider.base_azure_url : BASE_AZURE_URL
        log :debug, "***** OmniAuth::Strategies::AzureActivedirectoryV2#client - options.base_azure_url = #{options.base_azure_url}"

        if provider.respond_to?(:authorize_params)
          options.authorize_params = provider.authorize_params
          log :debug, "***** OmniAuth::Strategies::AzureActivedirectoryV2#client - options.authorize_params = #{options.authorize_params}"
        end

        if provider.respond_to?(:domain_hint) && provider.domain_hint
          options.authorize_params.domain_hint = provider.domain_hint
          log :debug, "***** OmniAuth::Strategies::AzureActivedirectoryV2#client - options.authorize_params.domain_hint = #{options.authorize_params.domain_hint}"
        end

        if defined?(request) && request.params['prompt']
          options.authorize_params.prompt = request.params['prompt']
          log :debug, "***** OmniAuth::Strategies::AzureActivedirectoryV2#client - options.authorize_params.prompt = #{options.authorize_params.prompt}"
        end

        options.authorize_params.scope = if provider.respond_to?(:scope) && provider.scope
          provider.scope
        else
          DEFAULT_SCOPE
        end
        log :debug, "***** OmniAuth::Strategies::AzureActivedirectoryV2#client - options.authorize_params.scope = #{options.authorize_params.scope}"

        options.custom_policy =
          provider.respond_to?(:custom_policy) ? provider.custom_policy : nil
        log :debug, "***** OmniAuth::Strategies::AzureActivedirectoryV2#client - options.custom_policy = #{options.custom_policy}"

        options.client_options.authorize_url = "#{options.base_azure_url}/#{options.tenant_id}/oauth2/v2.0/authorize"
        log :debug, "***** OmniAuth::Strategies::AzureActivedirectoryV2#client - options.client_options.authorize_url = #{options.client_options.authorize_url}"
        options.client_options.token_url =
          if options.custom_policy
            "#{options.base_azure_url}/#{options.tenant_id}/#{options.custom_policy}/oauth2/v2.0/token"
          else
            "#{options.base_azure_url}/#{options.tenant_id}/oauth2/v2.0/token"
          end
        log :debug, "***** OmniAuth::Strategies::AzureActivedirectoryV2#client - options.client_options.token_url = #{options.client_options.token_url}"

        log :debug, "***** OmniAuth::Strategies::AzureActivedirectoryV2#client - Calling super"
        super
      end

      uid { raw_info['oid'] }

      info do
        {
          name: raw_info['name'],
          email: raw_info['email'] || raw_info['upn'],
          nickname: raw_info['unique_name'],
          first_name: raw_info['given_name'],
          last_name: raw_info['family_name']
        }
      end

      extra do
        { raw_info: raw_info }
      end

      def callback_url
        full_host + callback_path
      end

      # https://docs.microsoft.com/en-us/azure/active-directory/develop/id-tokens
      #
      # Some account types from Microsoft seem to only have a decodable ID token,
      # with JWT unable to decode the access token. Information is limited in those
      # cases. Other account types provide an expanded set of data inside the auth
      # token, which does decode as a JWT.
      #
      # Merge the two, allowing the expanded auth token data to overwrite the ID
      # token data if keys collide, and use this as raw info.
      #
      def raw_info
        log :debug, "***** OmniAuth::Strategies::AzureActivedirectoryV2#raw_info - Starting"
        if @raw_info.nil?
          log :debug, "***** OmniAuth::Strategies::AzureActivedirectoryV2#raw_info - @raw_info was nil"
          id_token_data = begin
            log :debug, "***** OmniAuth::Strategies::AzureActivedirectoryV2#raw_info - Decoding access_token.params['id_token'] = #{access_token.params['id_token']}"
            ::JWT.decode(access_token.params['id_token'], nil, false).first
          rescue StandardError => e
            log :debug, "***** OmniAuth::Strategies::AzureActivedirectoryV2#raw_info - Caught error #{e.inspect} while decoding access_token.params['id_token']"
            {}
          end
          log :debug, "***** OmniAuth::Strategies::AzureActivedirectoryV2#raw_info - id_token_data is #{id_token_data}"
          auth_token_data = begin
            log :debug, "***** OmniAuth::Strategies::AzureActivedirectoryV2#raw_info - Decoding access_token.token = #{access_token.token}"
            ::JWT.decode(access_token.token, nil, false).first
          rescue StandardError => e
            log :debug, "***** OmniAuth::Strategies::AzureActivedirectoryV2#raw_info - Caught error #{e.inspect} while decoding access_token.token"
            {}
          end
          log :debug, "***** OmniAuth::Strategies::AzureActivedirectoryV2#raw_info - auth_token_data is #{auth_token_data}"

          id_token_data.merge!(auth_token_data)
          log :debug, "***** OmniAuth::Strategies::AzureActivedirectoryV2#raw_info - id_token_data is now #{id_token_data}"
          @raw_info = id_token_data
        end

        log :debug, "***** OmniAuth::Strategies::AzureActivedirectoryV2#raw_info - Returning #{@raw_info}"
        @raw_info
      end
    end
  end
end
