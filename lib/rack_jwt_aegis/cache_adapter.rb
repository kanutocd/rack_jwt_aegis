# frozen_string_literal: true

module RackJwtAegis
  class CacheAdapter
    def self.build(store_type, options = {})
      case store_type
      when :memory
        MemoryAdapter.new(options)
      when :redis
        RedisAdapter.new(options)
      when :memcached
        MemcachedAdapter.new(options)
      when :solid_cache
        SolidCacheAdapter.new(options)
      else
        raise ConfigurationError, "Unsupported cache store: #{store_type}"
      end
    end

    def initialize(options = {})
      @options = options
    end

    # Abstract methods - must be implemented by subclasses
    def read(key)
      raise NotImplementedError, 'Subclass must implement #read'
    end

    def write(key, value, expires_in: nil)
      raise NotImplementedError, 'Subclass must implement #write'
    end

    def delete(key)
      raise NotImplementedError, 'Subclass must implement #delete'
    end

    def exist?(key)
      !read(key).nil?
    end

    def clear
      raise NotImplementedError, 'Subclass must implement #clear'
    end

    # Helper methods
    protected

    def serialize_value(value)
      case value
      when String, Numeric, TrueClass, FalseClass, NilClass
        value
      else
        JSON.generate(value)
      end
    end

    def deserialize_value(value, _original_type = nil)
      return value if value.nil?
      return value unless value.is_a?(String)

      # Try to parse as JSON, fallback to string
      begin
        JSON.parse(value)
      rescue JSON::ParserError
        value
      end
    end
  end

  # Memory-based cache adapter (for development/testing)
  class MemoryAdapter < CacheAdapter
    def initialize(options = {})
      super
      @store = {}
      @expires = {}
      @mutex = Mutex.new
    end

    def read(key)
      @mutex.synchronize do
        cleanup_expired
        value = @store[key.to_s]
        deserialize_value(value)
      end
    end

    def write(key, value, expires_in: nil)
      @mutex.synchronize do
        key_str = key.to_s
        @store[key_str] = serialize_value(value)

        if expires_in
          @expires[key_str] = Time.now + expires_in
        else
          @expires.delete(key_str)
        end

        true
      end
    end

    def delete(key)
      @mutex.synchronize do
        key_str = key.to_s
        @store.delete(key_str)
        @expires.delete(key_str)
        true
      end
    end

    def clear
      @mutex.synchronize do
        @store.clear
        @expires.clear
        true
      end
    end

    private

    def cleanup_expired
      return unless @expires.any?

      now = Time.now
      expired_keys = @expires.select { |_, expiry| expiry < now }.keys

      expired_keys.each do |key|
        @store.delete(key)
        @expires.delete(key)
      end
    end
  end

  # Redis cache adapter
  class RedisAdapter < CacheAdapter
    def initialize(options = {})
      super
      require 'redis' unless defined?(Redis)

      @redis = options[:redis_instance] || Redis.new(options)
    rescue LoadError
      raise CacheError, "Redis gem not found. Add 'gem \"redis\"' to your Gemfile."
    end

    def read(key)
      value = @redis.get(key.to_s)
      deserialize_value(value)
    rescue StandardError => e
      raise CacheError, "Redis read error: #{e.message}"
    end

    def write(key, value, expires_in: nil)
      key_str = key.to_s
      serialized_value = serialize_value(value)

      if expires_in
        @redis.setex(key_str, expires_in.to_i, serialized_value)
      else
        @redis.set(key_str, serialized_value)
      end

      true
    rescue StandardError => e
      raise CacheError, "Redis write error: #{e.message}"
    end

    def delete(key)
      @redis.del(key.to_s).positive?
    rescue StandardError => e
      raise CacheError, "Redis delete error: #{e.message}"
    end

    def clear
      @redis.flushdb
      true
    rescue StandardError => e
      raise CacheError, "Redis clear error: #{e.message}"
    end
  end

  # Memcached cache adapter
  class MemcachedAdapter < CacheAdapter
    def initialize(options = {})
      super
      require 'dalli' unless defined?(Dalli)

      @memcached = Dalli::Client.new(options[:servers] || 'localhost:11211', options)
    rescue LoadError
      raise CacheError, "Dalli gem not found. Add 'gem \"dalli\"' to your Gemfile."
    end

    def read(key)
      value = @memcached.get(key.to_s)
      deserialize_value(value)
    rescue StandardError => e
      raise CacheError, "Memcached read error: #{e.message}"
    end

    def write(key, value, expires_in: nil)
      serialized_value = serialize_value(value)
      @memcached.set(key.to_s, serialized_value, expires_in&.to_i)
      true
    rescue StandardError => e
      raise CacheError, "Memcached write error: #{e.message}"
    end

    def delete(key)
      @memcached.delete(key.to_s)
      true
    rescue StandardError => e
      raise CacheError, "Memcached delete error: #{e.message}"
    end

    def clear
      @memcached.flush
      true
    rescue StandardError => e
      raise CacheError, "Memcached clear error: #{e.message}"
    end
  end

  # Solid Cache adapter (Rails 8+)
  class SolidCacheAdapter < CacheAdapter
    def initialize(options = {})
      super

      # Solid Cache should be available in Rails environment
      unless defined?(SolidCache)
        raise CacheError, "SolidCache not available. Ensure you're using Rails 8+ with Solid Cache configured."
      end

      @cache = options[:cache_instance] || SolidCache
    end

    def read(key)
      value = @cache.read(key.to_s)
      deserialize_value(value)
    rescue StandardError => e
      raise CacheError, "SolidCache read error: #{e.message}"
    end

    def write(key, value, expires_in: nil)
      serialized_value = serialize_value(value)
      @cache.write(key.to_s, serialized_value, expires_in: expires_in)
      true
    rescue StandardError => e
      raise CacheError, "SolidCache write error: #{e.message}"
    end

    def delete(key)
      @cache.delete(key.to_s)
      true
    rescue StandardError => e
      raise CacheError, "SolidCache delete error: #{e.message}"
    end

    def clear
      @cache.clear
      true
    rescue StandardError => e
      raise CacheError, "SolidCache clear error: #{e.message}"
    end
  end
end
