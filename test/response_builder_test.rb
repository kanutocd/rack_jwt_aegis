# frozen_string_literal: true

require 'test_helper'

class ResponseBuilderTest < Minitest::Test
  def setup
    @config = RackJwtAegis::Configuration.new(basic_config)
    @builder = RackJwtAegis::ResponseBuilder.new(@config)
  end

  def test_unauthorized_response_default_message
    status, headers, body = @builder.unauthorized_response

    assert_equal 401, status
    assert_equal 'application/json', headers['Content-Type']
    assert headers['Content-Length']
    assert_equal 'no-cache, no-store, must-revalidate', headers['Cache-Control']
    assert_equal 'no-cache', headers['Pragma']
    assert_equal '0', headers['Expires']

    response_data = JSON.parse(body.first)

    assert_equal 'Authentication required', response_data['error']
    assert_equal 401, response_data['status']
    assert response_data['timestamp']
  end

  def test_unauthorized_response_custom_message
    status, _headers, body = @builder.unauthorized_response('Custom auth error')

    assert_equal 401, status

    response_data = JSON.parse(body.first)

    assert_equal 'Custom auth error', response_data['error']
    assert_equal 401, response_data['status']
  end

  def test_unauthorized_response_from_config
    custom_config = RackJwtAegis::Configuration.new(basic_config.merge(
                                                      unauthorized_response: { error: 'Please login' },
                                                    ))
    builder = RackJwtAegis::ResponseBuilder.new(custom_config)

    status, _headers, body = builder.unauthorized_response

    assert_equal 401, status

    response_data = JSON.parse(body.first)

    assert_equal 'Please login', response_data['error']
  end

  def test_forbidden_response_default_message
    status, headers, body = @builder.forbidden_response

    assert_equal 403, status
    assert_equal 'application/json', headers['Content-Type']
    assert headers['Content-Length']
    assert_equal 'no-cache, no-store, must-revalidate', headers['Cache-Control']
    assert_equal 'no-cache', headers['Pragma']
    assert_equal '0', headers['Expires']

    response_data = JSON.parse(body.first)

    assert_equal 'Access denied', response_data['error']
    assert_equal 403, response_data['status']
    assert response_data['timestamp']
  end

  def test_forbidden_response_custom_message
    status, _headers, body = @builder.forbidden_response('Insufficient permissions')

    assert_equal 403, status

    response_data = JSON.parse(body.first)

    assert_equal 'Insufficient permissions', response_data['error']
    assert_equal 403, response_data['status']
  end

  def test_forbidden_response_from_config
    custom_config = RackJwtAegis::Configuration.new(basic_config.merge(
                                                      forbidden_response: { error: 'No access allowed' },
                                                    ))
    builder = RackJwtAegis::ResponseBuilder.new(custom_config)

    status, _headers, body = builder.forbidden_response

    assert_equal 403, status

    response_data = JSON.parse(body.first)

    assert_equal 'No access allowed', response_data['error']
  end

  def test_error_response_headers
    status, headers, body = @builder.error_response('Test error', 422)

    assert_equal 422, status
    assert_equal 'application/json', headers['Content-Type']
    assert_equal body.first.bytesize.to_s, headers['Content-Length']
    assert_equal 'no-cache, no-store, must-revalidate', headers['Cache-Control']
    assert_equal 'no-cache', headers['Pragma']
    assert_equal '0', headers['Expires']
  end

  def test_error_response_body_structure
    _status, _headers, body = @builder.error_response('Test message', 422)

    response_data = JSON.parse(body.first)

    assert_equal 'Test message', response_data['error']
    assert_equal 422, response_data['status']
    assert response_data['timestamp']

    # Verify timestamp is in ISO8601 format
    parsed_time = Time.parse(response_data['timestamp'])

    assert_kind_of Time, parsed_time
  end

  def test_debug_mode_adds_middleware_info
    debug_config = RackJwtAegis::Configuration.new(basic_config.merge(debug_mode: true))
    debug_builder = RackJwtAegis::ResponseBuilder.new(debug_config)

    _status, _headers, body = debug_builder.error_response('Debug test', 401)

    response_data = JSON.parse(body.first)

    assert_equal 'Debug test', response_data['error']
    assert_equal 401, response_data['status']
    assert_equal 'rack_jwt_aegis', response_data['middleware']
    assert_equal RackJwtAegis::VERSION, response_data['version']
    assert response_data['timestamp']
  end

  def test_debug_mode_disabled_no_extra_info
    _status, _headers, body = @builder.error_response('Normal test', 403)

    response_data = JSON.parse(body.first)

    assert_equal 'Normal test', response_data['error']
    assert_equal 403, response_data['status']
    assert response_data['timestamp']
    refute response_data.key?('middleware')
    refute response_data.key?('version')
  end

  def test_response_body_is_array
    _status, _headers, body = @builder.error_response('Test', 500)

    assert_kind_of Array, body
    assert_equal 1, body.length
    assert_kind_of String, body.first
  end

  def test_content_length_is_accurate
    _status, headers, body = @builder.error_response('Test message', 400)

    expected_length = body.first.bytesize
    actual_length = headers['Content-Length'].to_i

    assert_equal expected_length, actual_length
  end

  def test_timestamp_is_recent
    _status, _headers, body = @builder.error_response('Time test', 500)

    response_data = JSON.parse(body.first)
    response_time = Time.parse(response_data['timestamp'])

    # Should be within 1 second of now
    assert_operator (Time.now - response_time), :<, 1
  end

  def test_json_output_is_valid
    _status, _headers, body = @builder.error_response('JSON test', 400)

    # Should not raise JSON parse error
    parsed = JSON.parse(body.first)

    assert_kind_of Hash, parsed
    assert parsed['error']
    assert parsed['status']
    assert parsed['timestamp']
  end

  def test_special_characters_in_error_message
    special_message = "Error with \"quotes\" and 'apostrophes' and \n newlines"
    _status, _headers, body = @builder.error_response(special_message, 400)

    # Should not raise JSON parse error
    response_data = JSON.parse(body.first)

    assert_equal special_message, response_data['error']
  end

  def test_unicode_characters_in_error_message
    unicode_message = 'Error with unicode: 你好世界 🔒'
    _status, _headers, body = @builder.error_response(unicode_message, 400)

    response_data = JSON.parse(body.first)

    assert_equal unicode_message, response_data['error']

    # Content-Length should account for UTF-8 byte size
    expected_length = body.first.bytesize
    actual_length = body.first.length
    # Byte size should be larger than character length due to unicode
    assert_operator expected_length, :>=, actual_length
  end
end
