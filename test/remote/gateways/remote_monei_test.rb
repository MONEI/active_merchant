require 'test_helper'

class RemoteMoneiTest < Test::Unit::TestCase
  def setup
    @gateway = MoneiGateway.new(
      fixtures(:monei)
    )

    @amount = 100
    @credit_card = credit_card('4548812049400004', month: 12, year: 2020, verification_value: '123')
    @declined_card = credit_card('5453010000059675')

    @options = {
      billing_address: address,
      description: 'Store Purchase'
    }
  end

  def random_order_id
    SecureRandom.hex(16)
  end

  def test_successful_purchase
    options = @options.merge({order_id: random_order_id()})
    response = @gateway.purchase(@amount, @credit_card, options)

    assert_success response
    assert_equal 'Transaction approved', response.message
  end

  def test_successful_purchase_with_3ds
    options = @options.merge!({
      order_id: random_order_id(),
      three_d_secure: {
        eci: '05',
        cavv: 'AAACAgSRBklmQCFgMpEGAAAAAAA=',
        xid: 'CAACCVVUlwCXUyhQNlSXAAAAAAA='
      }
    })
    response = @gateway.purchase(@amount, @credit_card, options)

    assert_success response
    assert_equal 'Transaction approved', response.message
  end

  def test_failed_purchase
    options = @options.merge({order_id: random_order_id()})
    response = @gateway.purchase(@amount, @declined_card, options)
    assert_failure response
    assert_equal 'Card number declined by processor', response.message
  end

  def test_failed_purchase_with_3ds
    options = @options.merge!({
      order_id: random_order_id(),
      three_d_secure: {
        eci: '05',
        cavv: 'INVALID_Verification_ID',
        xid: 'CAACCVVUlwCXUyhQNlSXAAAAAAA='
      }
    })
    response = @gateway.purchase(@amount, @credit_card, options)
    assert_failure response
    assert_equal 'Invalid 3DSecure Verification ID', response.message
  end

  def test_successful_authorize_and_capture
    options = @options.merge({order_id: random_order_id()})
    auth = @gateway.authorize(@amount, @credit_card, options)
    assert_success auth

    assert capture = @gateway.capture(@amount, auth.authorization)
    assert_success capture
  end

  def test_failed_authorize
    options = @options.merge({order_id: random_order_id()})
    response = @gateway.authorize(@amount, @declined_card, options)
    assert_failure response
  end

  def test_partial_capture
    options = @options.merge({order_id: random_order_id()})
    auth = @gateway.authorize(@amount, @credit_card, options)
    assert_success auth

    assert capture = @gateway.capture(@amount - 1, auth.authorization)
    assert_success capture
  end

  def test_multi_partial_capture
    options = @options.merge({order_id: random_order_id()})
    auth = @gateway.authorize(@amount, @credit_card, options)
    assert_success auth

    assert capture = @gateway.capture(@amount - 1, auth.authorization)
    assert_success capture

    assert capture = @gateway.capture(@amount - 1, auth.authorization)
    assert_failure capture
  end

  def test_failed_capture
    response = @gateway.capture(nil, '')
    assert_failure response
  end

  def test_successful_refund
    options = @options.merge({order_id: random_order_id()})
    purchase = @gateway.purchase(@amount, @credit_card, options)
    assert_success purchase

    assert refund = @gateway.refund(@amount, purchase.authorization)
    assert_success refund
  end

  def test_partial_refund
    options = @options.merge({order_id: random_order_id()})
    purchase = @gateway.purchase(@amount, @credit_card, options)
    assert_success purchase

    assert refund = @gateway.refund(@amount - 1, purchase.authorization)
    assert_success refund
  end

  def test_multi_partial_refund
    options = @options.merge({order_id: random_order_id()})
    purchase = @gateway.purchase(@amount, @credit_card, options)
    assert_success purchase

    assert refund = @gateway.refund(@amount - 1, purchase.authorization)
    assert_success refund

    assert refund = @gateway.refund(@amount - 1, purchase.authorization)
    assert_failure refund
  end

  def test_failed_refund
    response = @gateway.refund(nil, '')
    assert_failure response
  end

  def test_successful_void
    options = @options.merge({order_id: random_order_id()})
    auth = @gateway.authorize(@amount, @credit_card, options)
    assert_success auth

    assert void = @gateway.void(auth.authorization)
    assert_success void
  end

  def test_failed_void
    response = @gateway.void('')
    assert_failure response
  end

  def test_successful_verify
    options = @options.merge({order_id: random_order_id()})
    response = @gateway.verify(@credit_card, options)
    assert_success response
    assert_equal 'Transaction approved', response.message
  end

  def test_failed_verify
    options = @options.merge({order_id: random_order_id()})
    response = @gateway.verify(@declined_card, options)
    assert_failure response

    assert_equal 'Card number declined by processor', response.message
  end

  def test_invalid_login
    gateway = MoneiGateway.new(
      api_key: 'invalid'
    )
    options = @options.merge({order_id: random_order_id()})
    response = gateway.purchase(@amount, @credit_card, options)
    assert_failure response
  end
end
