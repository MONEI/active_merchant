require 'nokogiri'

module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    #
    # == Monei gateway
    # This class implements Monei gateway for Active Merchant. For more information about Monei
    # gateway please go to http://www.monei.net
    #
    # === Setup
    # In order to set-up the gateway you need two paramaters: account_id and password.
    # Request that data to Monei.
    class MoneiGateway < Gateway
      self.live_url = self.test_url = 'https://pay.monei.net/ws/v1/'

      self.supported_countries = ['AD', 'AT', 'BE', 'BG', 'CA', 'CH', 'CY', 'CZ', 'DE', 'DK', 'EE', 'ES', 'FI', 'FO', 'FR', 'GB', 'GI', 'GR', 'HU', 'IE', 'IL', 'IS', 'IT', 'LI', 'LT', 'LU', 'LV', 'MT', 'NL', 'NO', 'PL', 'PT', 'RO', 'SE', 'SI', 'SK', 'TR', 'US', 'VA']
      self.default_currency = 'EUR'
      self.supported_cardtypes = [:visa, :master, :maestro, :jcb, :american_express]

      self.homepage_url = 'http://www.monei.net/'
      self.display_name = 'Monei'

      # Constructor
      #
      # options - Hash containing the gateway credentials, ALL MANDATORY
      #           :account_id      Account ID
      #           :password        Account password
      #
      def initialize(options={})
        requires!(options, :account_id, :password)
        super
      end

      # Public: Performs purchase operation
      #
      # money       - Amount of purchase
      # credit_card - Credit card
      # options     - Hash containing purchase options
      #               :order_id         Merchant created id for the purchase
      #               :billing_address  Hash with billing address information
      #               :description      Merchant created purchase description (optional)
      #               :currency         Sale currency to override money object or default (optional)
      #
      # Returns Active Merchant response object
      def purchase(money, credit_card, options={})
        execute_new_order(:purchase, money, credit_card, options)
      end

      # Public: Performs authorization operation
      #
      # money       - Amount to authorize
      # credit_card - Credit card
      # options     - Hash containing authorization options
      #               :order_id         Merchant created id for the authorization
      #               :billing_address  Hash with billing address information
      #               :description      Merchant created authorization description (optional)
      #               :currency         Sale currency to override money object or default (optional)
      #
      # Returns Active Merchant response object
      def authorize(money, credit_card, options={})
        execute_new_order(:authorize, money, credit_card, options)
      end

      # Public: Performs capture operation on previous authorization
      #
      # money         - Amount to capture
      # authorization - Reference to previous authorization, obtained from response object returned by authorize
      # options       - Hash containing capture options
      #                 :order_id         Merchant created id for the authorization (optional)
      #                 :description      Merchant created authorization description (optional)
      #                 :currency         Sale currency to override money object or default (optional)
      #
      # Note: you should pass either order_id or description
      #
      # Returns Active Merchant response object
      def capture(money, authorization, options={})
        execute_dependant(:capture, money, authorization, options)
      end

      # Public: Refunds from previous purchase
      #
      # money         - Amount to refund
      # authorization - Reference to previous purchase, obtained from response object returned by purchase
      # options       - Hash containing refund options
      #                 :order_id         Merchant created id for the authorization (optional)
      #                 :description      Merchant created authorization description (optional)
      #                 :currency         Sale currency to override money object or default (optional)
      #
      # Note: you should pass either order_id or description
      #
      # Returns Active Merchant response object
      def refund(money, authorization, options={})
        execute_dependant(:refund, money, authorization, options)
      end

      # Public: Voids previous authorization
      #
      # authorization - Reference to previous authorization, obtained from response object returned by authorize
      # options       - Hash containing capture options
      #                 :order_id         Merchant created id for the authorization (optional)
      #
      # Returns Active Merchant response object
      def void(authorization, options={})
        execute_dependant(:void, nil, authorization, options)
      end

      # Public: Verifies credit card. Does this by doing a authorization of 1.00 Euro and then voiding it.
      #
      # credit_card - Credit card
      # options     - Hash containing authorization options
      #               :order_id         Merchant created id for the authorization
      #               :billing_address  Hash with billing address information
      #               :description      Merchant created authorization description (optional)
      #               :currency         Sale currency to override money object or default (optional)
      #
      # Returns Active Merchant response object of Authorization operation
      def verify(credit_card, options={})
        MultiResponse.run(:use_first_response) do |r|
          r.process { authorize(100, credit_card, options) }
          r.process(:ignore_result) { void(r.authorization, options) }
        end
      end

      private

      # Private: Execute purchase or authorize operation
      def execute_new_order(action, money, credit_card, options)
        request = build_request

        add_identification_new_order(request, options)
        add_transaction(request, action, money, options)
        add_payment(request, credit_card)
        add_customer(request, credit_card, options)
        add_three_d_secure(request, options)

        commit(request, action)
      end

      # Private: Execute operation that depends on authorization code from previous purchase or authorize operation
      def execute_dependant(action, money, authorization, options)
        request = build_request

        add_identification_authorization(request, authorization, options)
        add_transaction(request, action, money, options)

        commit(request, action)
      end

      # Private: Build request object
      def build_request
        request = {}
        request[:account_id] = options[:account_id]
        request[:signature] = Base64.strict_encode64(@options[:password]).chomp
        request[:test] = test? ? 'true' : 'false'
        request
      end

      # Private: Add identification part to request for new orders
      def add_identification_new_order(request, options)
        requires!(options, :order_id)
        request[:order_id] = options[:order_id]
      end

      # Private: Add identification part to request for orders that depend on authorization from previous operation
      def add_identification_authorization(request, authorization, options)
        request[:monei_order_id] = authorization
        request[:order_id] = options[:order_id]
      end

      # Private: Add payment part to request
      def add_transaction(request, action, money, options)
        request[:transaction_type] = translate_payment_code(action)
        request[:description] = options[:description] || options[:order_id]
        unless money.nil?
          request[:amount] = amount(money)
          request[:currency] = options[:currency] || currency(money)
        end
      end

      # Private: Add payment method to request
      def add_payment(request, credit_card)
        request[:payment_card_number] = credit_card.number
        request[:payment_card_exp_month] = credit_card.month
        request[:payment_card_exp_year] = credit_card.year
        request[:payment_card_cvc] = credit_card.verification_value
      end

      # Private: Add customer part to request
      def add_customer(request, credit_card, options)
        requires!(options, :billing_address)
        address = options[:billing_address]

        request[:customer_first_name] = credit_card.first_name
        request[:customer_last_name] = credit_card.last_name
        request[:customer_email] = options[:email] || 'support@monei.net'

        request[:customer_billing_address1] = address[:address1].to_s
        request[:customer_billing_city] = address[:city].to_s
        request[:customer_billing_state] = address[:state].to_s if address.has_key? :state
        request[:customer_billing_zip] = address[:zip].to_s
        request[:customer_billing_country] = address[:country].to_s
      end

      # Private : Convert ECI to ResultIndicator
      # Possible ECI values:
      # 02 or 05 - Fully Authenticated Transaction
      # 00 or 07 - Non 3D Secure Transaction
      # Possible ResultIndicator values:
      # 01 = MASTER_3D_ATTEMPT
      # 02 = MASTER_3D_SUCCESS
      # 05 = VISA_3D_SUCCESS
      # 06 = VISA_3D_ATTEMPT
      # 07 = DEFAULT_E_COMMERCE
      def eci_to_result_indicator(eci)
        case eci
        when '02', '05'
          return eci
        else
          return '07'
        end
      end

      # Private : Add the 3DSecure infos to request
      def add_three_d_secure(request, options)
        if options[:three_d_secure]
          request[:authentication_type] = '3DSecure'
          request[:authentication_eci] = eci_to_result_indicator options[:three_d_secure][:eci]
          request[:authentication_cavv] = options[:three_d_secure][:cavv]
          request[:authentication_xid] = options[:three_d_secure][:xid]
        end
      end

      # Private: Parse JSON response from Monei servers
      def parse(body)
        JSON.parse(body)
      end

      def json_error(raw_response)
        msg = 'Invalid response received from the MONEI API. Please contact support@monei.net if you continue to receive this message.'
        msg += " (The raw response returned by the API was #{raw_response.inspect})"
        {
          'status' => 'error',
          'message' => msg
        }
      end

      def response_error(raw_response)
        parse(raw_response)
      rescue JSON::ParserError
        json_error(raw_response)
      end

      def api_request(url, parameters, options = {})
        raw_response = response = nil
        begin
          raw_response = ssl_post(url, post_data(parameters), options)
          response = parse(raw_response)
        rescue ResponseError => e
          raw_response = e.response.body
          response = response_error(raw_response)
        rescue JSON::ParserError
          response = json_error(raw_response)
        end
        response
      end

      # Private: Send transaction to Monei servers and create AM response
      def commit(request, action)
        url = (test? ? test_url : live_url)
        endpoint = translate_action_endpoint(action) + '/active_merchant'

        response = api_request(url + endpoint, params(request, action), 'Content-Type' => 'application/json;charset=UTF-8')
        success = success_from(response)

        Response.new(
          success,
          message_from(response, success),
          response,
          authorization: authorization_from(response),
          test: test?,
          error_code: error_code_from(response, success)
        )
      end

      # Private: Decide success from servers response
      def success_from(response)
        response['result'] === 'completed'
      end

      # Private: Get message from servers response
      def message_from(response, success)
        success ? 'Transaction approved' : response.fetch('message', 'No error details')
      end

      # Private: Get error code from servers response
      def error_code_from(response, success)
        success ? nil : STANDARD_ERROR_CODE[:card_declined]
      end

      # Private: Get authorization code from servers response
      def authorization_from(response)
        response['monei_order_id']
      end

      # Private: Encode POST parameters
      def post_data(params)
        params.clone.to_json
      end

      # Private: generate request params depending on action
      def params(request, action)
        if action == :purchase || action == :authorize
          request = {
            'charge': request,
            'context': {
              ip: options[:ip] || '0.0.0.0',
              userAgent: options[:user_agent] || 'ActiveMerchant UA'
            }
          }
        end
        request
      end

      # Private: Translate AM operations to Monei operations codes
      def translate_payment_code(action)
        {
          purchase: 'sale',
          authorize: 'auth',
          capture: 'capture',
          refund: 'refund',
          void: 'void'
        }[action]
      end

      # Private: Translate AM operations to Monei endpoints
      def translate_action_endpoint(action)
        {
          purchase: 'charge',
          authorize: 'charge',
          capture: 'capture',
          refund: 'refund',
          void: 'void'
        }[action]
      end
    end
  end
end
