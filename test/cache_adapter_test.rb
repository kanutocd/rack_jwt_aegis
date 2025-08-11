# frozen_string_literal: true

require 'test_helper'

class CacheAdapterTest < Minitest::Test
  def test_build_memory_adapter
    adapter = RackJwtAegis::CacheAdapter.build(:memory, {})

    assert_instance_of RackJwtAegis::MemoryAdapter, adapter
  end

  def test_build_unsupported_adapter
    error = assert_raises(RackJwtAegis::ConfigurationError) do
      RackJwtAegis::CacheAdapter.build(:unsupported, {})
    end
    assert_equal 'Unsupported cache store: unsupported', error.message
  end

  def test_abstract_methods_not_implemented
    adapter = RackJwtAegis::CacheAdapter.new

    error = assert_raises(NotImplementedError) { adapter.read('key') }
    assert_equal 'Subclass must implement #read', error.message

    error = assert_raises(NotImplementedError) { adapter.write('key', 'value') }
    assert_equal 'Subclass must implement #write', error.message

    error = assert_raises(NotImplementedError) { adapter.delete('key') }
    assert_equal 'Subclass must implement #delete', error.message

    error = assert_raises(NotImplementedError) { adapter.clear }
    assert_equal 'Subclass must implement #clear', error.message
  end

  def test_exist_method_uses_read
    adapter = RackJwtAegis::CacheAdapter.new
    adapter.expects(:read).with('test_key').returns('value')

    assert adapter.exist?('test_key')

    adapter.expects(:read).with('missing_key').returns(nil)

    refute adapter.exist?('missing_key')
  end

  def test_serialize_value_primitives
    adapter = RackJwtAegis::CacheAdapter.new

    assert_equal 'hello', adapter.send(:serialize_value, 'hello')
    assert_equal 42, adapter.send(:serialize_value, 42)
    assert adapter.send(:serialize_value, true)
    refute adapter.send(:serialize_value, false)
    assert_nil adapter.send(:serialize_value, nil)
    assert_in_delta(3.14, adapter.send(:serialize_value, 3.14))
  end

  def test_serialize_value_complex
    adapter = RackJwtAegis::CacheAdapter.new

    hash_value = { 'key' => 'value', 'number' => 42 }
    array_value = [1, 2, 'three']

    assert_equal JSON.generate(hash_value), adapter.send(:serialize_value, hash_value)
    assert_equal JSON.generate(array_value), adapter.send(:serialize_value, array_value)
  end

  def test_deserialize_value_nil
    adapter = RackJwtAegis::CacheAdapter.new

    assert_nil adapter.send(:deserialize_value, nil)
  end

  def test_deserialize_value_non_string
    adapter = RackJwtAegis::CacheAdapter.new

    assert_equal 42, adapter.send(:deserialize_value, 42)
    assert adapter.send(:deserialize_value, true)
  end

  def test_deserialize_value_json_string
    adapter = RackJwtAegis::CacheAdapter.new

    json_hash = JSON.generate({ 'key' => 'value' })
    result = adapter.send(:deserialize_value, json_hash)

    assert_equal({ 'key' => 'value' }, result)

    json_array = JSON.generate([1, 2, 3])
    result = adapter.send(:deserialize_value, json_array)

    assert_equal [1, 2, 3], result
  end

  def test_deserialize_value_plain_string
    adapter = RackJwtAegis::CacheAdapter.new

    assert_equal 'plain string', adapter.send(:deserialize_value, 'plain string')
  end
end

class MemoryAdapterTest < Minitest::Test
  def setup
    @adapter = RackJwtAegis::MemoryAdapter.new
  end

  def test_write_and_read
    @adapter.write('test_key', 'test_value')

    assert_equal 'test_value', @adapter.read('test_key')
  end

  def test_write_and_read_complex_value
    complex_value = { 'name' => 'John', 'age' => 30, 'active' => true }
    @adapter.write('user', complex_value)

    assert_equal complex_value, @adapter.read('user')
  end

  def test_read_nonexistent_key
    assert_nil @adapter.read('nonexistent')
  end

  def test_write_with_expiration
    current_time = Time.now
    Time.stubs(:now).returns(current_time)

    @adapter.write('expiring_key', 'value', expires_in: 1)

    assert_equal 'value', @adapter.read('expiring_key')

    # Mock time to simulate expiration
    Time.stubs(:now).returns(current_time + 2)

    assert_nil @adapter.read('expiring_key')
  end

  def test_delete
    @adapter.write('to_delete', 'value')

    assert_equal 'value', @adapter.read('to_delete')

    result = @adapter.delete('to_delete')

    assert result
    assert_nil @adapter.read('to_delete')
  end

  def test_exist
    refute @adapter.exist?('missing')

    @adapter.write('existing', 'value')

    assert @adapter.exist?('existing')
  end

  def test_clear
    @adapter.write('key1', 'value1')
    @adapter.write('key2', 'value2')

    result = @adapter.clear

    assert result
    assert_nil @adapter.read('key1')
    assert_nil @adapter.read('key2')
  end

  def test_key_conversion_to_string
    @adapter.write(:symbol_key, 'value')

    assert_equal 'value', @adapter.read('symbol_key')
    assert_equal 'value', @adapter.read(:symbol_key)
  end

  def test_cleanup_expired_on_read
    current_time = Time.now
    Time.stubs(:now).returns(current_time)

    @adapter.write('key1', 'value1', expires_in: 1)
    @adapter.write('key2', 'value2', expires_in: 10)

    # Mock time to expire first key but not second
    Time.stubs(:now).returns(current_time + 2)

    # This should trigger cleanup
    @adapter.read('any_key')

    # Verify expired key is cleaned up
    assert_nil @adapter.instance_variable_get(:@store)['key1']
    assert @adapter.instance_variable_get(:@store).key?('key2')
  end

  def test_thread_safety
    threads = []
    results = {}

    10.times do |i|
      threads << Thread.new do
        @adapter.write("key_#{i}", "value_#{i}")
        results[i] = @adapter.read("key_#{i}")
      end
    end

    threads.each(&:join)

    10.times do |i|
      assert_equal "value_#{i}", results[i]
    end
  end
end

class RedisAdapterTest < Minitest::Test
  def setup
    # Skip Redis tests if Redis gem is not available
    skip 'Redis gem not available' unless defined?(Redis)

    @mock_redis = mock
    @adapter = RackJwtAegis::RedisAdapter.new(redis_instance: @mock_redis)
  end

  def test_initialization_without_redis_gem
    # Test the LoadError path
    RackJwtAegis::RedisAdapter.any_instance.stubs(:require).raises(LoadError)

    error = assert_raises(RackJwtAegis::CacheError) do
      RackJwtAegis::RedisAdapter.new
    end
    assert_match(/Redis gem not found/, error.message)
  end

  def test_read
    @mock_redis.expects(:get).with('test_key').returns('"test_value"')

    assert_equal 'test_value', @adapter.read('test_key')
  end

  def test_read_nil
    @mock_redis.expects(:get).with('missing').returns(nil)

    assert_nil @adapter.read('missing')
  end

  def test_read_error
    @mock_redis.expects(:get).raises(StandardError.new('Connection failed'))

    error = assert_raises(RackJwtAegis::CacheError) do
      @adapter.read('key')
    end
    assert_match(/Redis read error/, error.message)
  end

  def test_write
    @mock_redis.expects(:set).with('key', 'value').returns('OK')
    result = @adapter.write('key', 'value')

    assert result
  end

  def test_write_with_expiration
    @mock_redis.expects(:setex).with('key', 300, 'value').returns('OK')
    result = @adapter.write('key', 'value', expires_in: 300)

    assert result
  end

  def test_write_error
    @mock_redis.expects(:set).raises(StandardError.new('Write failed'))

    error = assert_raises(RackJwtAegis::CacheError) do
      @adapter.write('key', 'value')
    end
    assert_match(/Redis write error/, error.message)
  end

  def test_delete
    @mock_redis.expects(:del).with('key').returns(1)

    assert @adapter.delete('key')
  end

  def test_delete_nonexistent
    @mock_redis.expects(:del).with('key').returns(0)

    refute @adapter.delete('key')
  end

  def test_delete_error
    @mock_redis.expects(:del).raises(StandardError.new('Delete failed'))

    error = assert_raises(RackJwtAegis::CacheError) do
      @adapter.delete('key')
    end
    assert_match(/Redis delete error/, error.message)
  end

  def test_clear
    @mock_redis.expects(:flushdb).returns('OK')
    result = @adapter.clear

    assert result
  end

  def test_clear_error
    @mock_redis.expects(:flushdb).raises(StandardError.new('Flush failed'))

    error = assert_raises(RackJwtAegis::CacheError) do
      @adapter.clear
    end
    assert_match(/Redis clear error/, error.message)
  end
end

class MemcachedAdapterTest < Minitest::Test
  def setup
    skip 'Dalli gem not available' unless defined?(Dalli)

    @mock_memcached = mock
    @adapter = RackJwtAegis::MemcachedAdapter.new
    @adapter.instance_variable_set(:@memcached, @mock_memcached)
  end

  def test_initialization_without_dalli_gem
    RackJwtAegis::MemcachedAdapter.any_instance.stubs(:require).raises(LoadError)

    error = assert_raises(RackJwtAegis::CacheError) do
      RackJwtAegis::MemcachedAdapter.new
    end
    assert_match(/Dalli gem not found/, error.message)
  end

  def test_read
    @mock_memcached.expects(:get).with('key').returns('value')

    assert_equal 'value', @adapter.read('key')
  end

  def test_read_error
    @mock_memcached.expects(:get).raises(StandardError.new('Connection failed'))

    error = assert_raises(RackJwtAegis::CacheError) do
      @adapter.read('key')
    end
    assert_match(/Memcached read error/, error.message)
  end

  def test_write
    @mock_memcached.expects(:set).with('key', 'value', nil).returns(true)
    result = @adapter.write('key', 'value')

    assert result
  end

  def test_write_with_expiration
    @mock_memcached.expects(:set).with('key', 'value', 300).returns(true)
    result = @adapter.write('key', 'value', expires_in: 300)

    assert result
  end

  def test_write_error
    @mock_memcached.expects(:set).raises(StandardError.new('Write failed'))

    error = assert_raises(RackJwtAegis::CacheError) do
      @adapter.write('key', 'value')
    end
    assert_match(/Memcached write error/, error.message)
  end

  def test_delete
    @mock_memcached.expects(:delete).with('key').returns(true)
    result = @adapter.delete('key')

    assert result
  end

  def test_delete_error
    @mock_memcached.expects(:delete).raises(StandardError.new('Delete failed'))

    error = assert_raises(RackJwtAegis::CacheError) do
      @adapter.delete('key')
    end
    assert_match(/Memcached delete error/, error.message)
  end

  def test_clear
    @mock_memcached.expects(:flush).returns(true)
    result = @adapter.clear

    assert result
  end

  def test_clear_error
    @mock_memcached.expects(:flush).raises(StandardError.new('Flush failed'))

    error = assert_raises(RackJwtAegis::CacheError) do
      @adapter.clear
    end
    assert_match(/Memcached clear error/, error.message)
  end
end

class SolidCacheAdapterTest < Minitest::Test
  def setup
    # Mock SolidCache constant and methods
    unless defined?(SolidCache)
      Object.const_set(:SolidCache, Class.new do
        def self.read(key); end
        def self.write(key, value, options = {}); end
        def self.delete(key); end
        def self.clear; end
      end)
    end

    @mock_cache = mock
    @adapter = RackJwtAegis::SolidCacheAdapter.new(cache_instance: @mock_cache)
  end

  def teardown
    Object.send(:remove_const, 'SolidCache') if defined?(SolidCache)
  end

  def test_initialization_without_solid_cache
    Object.send(:remove_const, 'SolidCache') if defined?(SolidCache)

    error = assert_raises(RackJwtAegis::CacheError) do
      RackJwtAegis::SolidCacheAdapter.new
    end
    assert_match(/SolidCache not available/, error.message)
  end

  def test_read
    @mock_cache.expects(:read).with('key').returns('value')

    assert_equal 'value', @adapter.read('key')
  end

  def test_read_error
    @mock_cache.expects(:read).raises(StandardError.new('Read failed'))

    error = assert_raises(RackJwtAegis::CacheError) do
      @adapter.read('key')
    end
    assert_match(/SolidCache read error/, error.message)
  end

  def test_write
    @mock_cache.expects(:write).with('key', 'value', expires_in: nil).returns(true)
    result = @adapter.write('key', 'value')

    assert result
  end

  def test_write_with_expiration
    @mock_cache.expects(:write).with('key', 'value', expires_in: 300).returns(true)
    result = @adapter.write('key', 'value', expires_in: 300)

    assert result
  end

  def test_write_error
    @mock_cache.expects(:write).raises(StandardError.new('Write failed'))

    error = assert_raises(RackJwtAegis::CacheError) do
      @adapter.write('key', 'value')
    end
    assert_match(/SolidCache write error/, error.message)
  end

  def test_delete
    @mock_cache.expects(:delete).with('key').returns(true)
    result = @adapter.delete('key')

    assert result
  end

  def test_delete_error
    @mock_cache.expects(:delete).raises(StandardError.new('Delete failed'))

    error = assert_raises(RackJwtAegis::CacheError) do
      @adapter.delete('key')
    end
    assert_match(/SolidCache delete error/, error.message)
  end

  def test_clear
    @mock_cache.expects(:clear).returns(true)
    result = @adapter.clear

    assert result
  end

  def test_clear_error
    @mock_cache.expects(:clear).raises(StandardError.new('Clear failed'))

    error = assert_raises(RackJwtAegis::CacheError) do
      @adapter.clear
    end
    assert_match(/SolidCache clear error/, error.message)
  end
end
