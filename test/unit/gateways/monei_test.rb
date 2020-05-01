require 'test_helper'

class MoneiTest < Test::Unit::TestCase
  include CommStub

  def setup
    @gateway = MoneiGateway.new(
      fixtures(:monei)
    )

    @credit_card = credit_card
    @amount = 100

    @options = {
      order_id: '1',
      billing_address: address,
      description: 'Store Purchase'
    }
  end

  def test_successful_purchase
    @gateway.expects(:ssl_post).returns(successful_purchase_response)

    response = @gateway.purchase(@amount, @credit_card, @options)
    assert_success response

    assert_equal '067574158f1f42499c31404752d52d06', response.authorization
    assert response.test?
  end

  def test_failed_purchase
    @gateway.expects(:ssl_post).returns(failed_purchase_response)

    response = @gateway.purchase(@amount, @credit_card, @options)
    assert_failure response
  end

  def test_successful_authorize
    @gateway.expects(:ssl_post).returns(successful_authorize_response)

    auth = @gateway.authorize(@amount, @credit_card, @options)
    assert_success auth
  end

  def test_failed_authorize
    @gateway.expects(:ssl_post).returns(failed_authorize_response)

    response = @gateway.authorize(@amount, @credit_card, @options)
    assert_failure response
  end

  def test_successful_capture
    @gateway.expects(:ssl_post).returns(successful_authorize_response)

    auth = @gateway.authorize(@amount, @credit_card, @options)
    assert_success auth

    @gateway.expects(:ssl_post).returns(successful_capture_response)

    assert capture = @gateway.capture(@amount, auth.authorization)
    assert_success capture
  end

  def test_failed_capture
    @gateway.expects(:ssl_post).returns(failed_capture_response)

    response = @gateway.capture(nil, '')
    assert_failure response
  end

  def test_successful_refund
    @gateway.expects(:ssl_post).returns(successful_purchase_response)

    purchase = @gateway.purchase(@amount, @credit_card, @options)
    assert_success purchase

    @gateway.expects(:ssl_post).returns(successful_refund_response)

    assert refund = @gateway.refund(@amount, purchase.authorization)
    assert_success refund
  end

  def test_failed_refund
    @gateway.expects(:ssl_post).returns(failed_refund_response)

    response = @gateway.refund(nil, '')
    assert_failure response
  end

  def test_successful_void
    @gateway.expects(:ssl_post).returns(successful_authorize_response)

    auth = @gateway.authorize(@amount, @credit_card, @options)
    assert_success auth

    @gateway.expects(:ssl_post).returns(successful_void_response)

    assert void = @gateway.void(auth.authorization)
    assert_success void
  end

  def test_failed_void
    @gateway.expects(:ssl_post).returns(failed_void_response)

    response = @gateway.void('')
    assert_failure response
  end

  def test_successful_verify
    response = stub_comms do
      @gateway.verify(@credit_card, @options)
    end.respond_with(successful_authorize_response, successful_void_response)
    assert_success response
  end

  def test_successful_verify_with_failed_void
    response = stub_comms do
      @gateway.verify(@credit_card, @options)
    end.respond_with(successful_authorize_response, failed_void_response)
    assert_success response
  end

  def test_failed_verify
    response = stub_comms do
      @gateway.verify(@credit_card, @options)
    end.respond_with(failed_authorize_response, successful_void_response)
    assert_failure response
  end

  def test_3ds_request
    authentication_type = '3DSecure'
    authentication_eci = '05'
    authentication_cavv = 'AAACAgSRBklmQCFgMpEGAAAAAAA='
    authentication_xid = 'CAACCVVUlwCXUyhQNlSXAAAAAAA='

    three_d_secure_options = {
      eci: authentication_eci,
      cavv: authentication_cavv,
      xid: authentication_xid
    }
    options = @options.merge!({
      three_d_secure: three_d_secure_options
    })
    stub_comms do
      @gateway.purchase(@amount, @credit_card, options)
    end.check_request do |endpoint, data, headers|
      assert_match(/\"authentication_type\":\"#{authentication_type}\"/, data)
      assert_match(/\"authentication_eci\":\"#{authentication_eci}\"/, data)
      assert_match(/\"authentication_cavv\":\"#{authentication_cavv}\"/, data)
      assert_match(/\"authentication_xid\":\"#{authentication_xid}\"/, data)
    end.respond_with(successful_purchase_response)
  end

  private

  def successful_purchase_response
    <<-RESPONSE
    {
      "account_id": "00000000-aaaa-bbbb-cccc-dddd123456789",
      "amount": "1.00",
      "currency": "EUR",
      "monei_order_id": "067574158f1f42499c31404752d52d06",
      "order_id": "1",
      "result": "completed",
      "test": "true",
      "timestamp": "2020-04-30T23:23:05.230Z",
      "message": "Transaction Approved",
      "transaction_type": "sale",
      "signature": "3dc52e4dbcc15cee5bb03cb7e3ab90708bf8b8a21818c0262ac05ec0c01780d0"
    }
    RESPONSE
  end

  def failed_purchase_response
    <<-RESPONSE
    {
      "status": "error",
      "message": "Card number declined by processor"
    }
    RESPONSE
  end

  def successful_authorize_response
    <<-RESPONSE
    {
      "account_id": "00000000-aaaa-bbbb-cccc-dddd123456789",
      "amount": "1.00",
      "currency": "EUR",
      "monei_order_id": "067574158f1f42499c31404752d52d06",
      "order_id": "1",
      "result": "completed",
      "test": "true",
      "timestamp": "2020-04-30T23:23:05.230Z",
      "message": "Transaction Approved",
      "transaction_type": "authorization",
      "signature": "3dc52e4dbcc15cee5bb03cb7e3ab90708bf8b8a21818c0262ac05ec0c01780d0"
    }
    RESPONSE
  end

  def failed_authorize_response
    <<-RESPONSE
    {
      "status": "error",
      "message": "Card number declined by processor"
    }
    RESPONSE
  end

  def successful_capture_response
    <<-RESPONSE
    {
      "account_id": "00000000-aaaa-bbbb-cccc-dddd123456789",
      "amount": "1.00",
      "currency": "EUR",
      "monei_order_id": "067574158f1f42499c31404752d52d06",
      "order_id": "1",
      "result": "completed",
      "test": "true",
      "timestamp": "2020-04-30T23:23:05.230Z",
      "message": "Transaction Approved",
      "transaction_type": "capture",
      "signature": "3dc52e4dbcc15cee5bb03cb7e3ab90708bf8b8a21818c0262ac05ec0c01780d0"
    }
    RESPONSE
  end

  def failed_capture_response
    <<-RESPONSE
    {
      "status": "error",
      "message": "Card number declined by processor"
    }
    RESPONSE
  end

  def successful_refund_response
    <<-RESPONSE
    {
      "account_id": "00000000-aaaa-bbbb-cccc-dddd123456789",
      "amount": "1.00",
      "currency": "EUR",
      "monei_order_id": "067574158f1f42499c31404752d52d06",
      "order_id": "1",
      "result": "completed",
      "test": "true",
      "timestamp": "2020-04-30T23:23:05.230Z",
      "message": "Transaction Approved",
      "transaction_type": "refund",
      "signature": "3dc52e4dbcc15cee5bb03cb7e3ab90708bf8b8a21818c0262ac05ec0c01780d0"
    }
    RESPONSE
  end

  def failed_refund_response
    <<-RESPONSE
    {
      "status": "error",
      "message": "Card number declined by processor"
    }
    RESPONSE
  end

  def successful_void_response
    <<-RESPONSE
    {
      "account_id": "00000000-aaaa-bbbb-cccc-dddd123456789",
      "amount": "1.00",
      "currency": "EUR",
      "monei_order_id": "067574158f1f42499c31404752d52d06",
      "order_id": "1",
      "result": "completed",
      "test": "true",
      "timestamp": "2020-04-30T23:23:05.230Z",
      "message": "Transaction Approved",
      "transaction_type": "void",
      "signature": "3dc52e4dbcc15cee5bb03cb7e3ab90708bf8b8a21818c0262ac05ec0c01780d0"
    }
    RESPONSE
  end

  def failed_void_response
    <<-RESPONSE
    {
      "status": "error",
      "message": "Card number declined by processor"
    }
    RESPONSE
  end
end
