class Redis
  class HashSet < Redis::RedisObject
    require 'enumerator'
    include Enumerable
    include Redis::RedisHelper::CoreCommands

    attr_reader :key, :options

    def initialize(key, *args)
      super
      @options[:marshal_keys] ||= {}
    end

    def []=(field, value)
      redis.hset(key, field, marshal(value, options[:marshal_keys][field]))
    end

    def [](field)
      unmarshal redis.hget(key, field), options[:marshal_keys][field]
    end

    def has_key?(field)
      redis.hexists(key, field)
    end
    alias_method :include?, :has_key?
    alias_method :key?, :has_key?
    alias_method :member?, :has_key?

    def delete!(field)
      redis.hdel(key, field)
    end

    def fetch(field, *args, &block)
      value = self[field]
      default = args[0]

      return value if value || (!default && !block_given?)
      block_given? ? block.call(field) : default
    end

    def keys
      redis.hkeys(key)
    end

    def values
      redis.hvals(key).map{|v| unmarshal(v)}
    end

    def all
      h = redis.hgetall(key) || {}
      h.each {|k,v| h[k] = unmarshal(v, options[:marshal_keys][k])}
      h
    end

    def each(&block)
      all.each(&block)
    end

    def each_key(&block)
      keys.each(&block)
    end

    def each_value(&block)
      values.each(&block)
    end

    def size
      redis.hlen(key)
    end
    alias_method :length, :size
    alias_method :count, :size

    def empty?
      size == 0
    end

    def clear
      redis.del(key)
    end

    def bulk_set(*args)
      raise ArgumentError, 'Argument to bulk_set must be hash of key/value pairs' unless args.last.is_a?(::Hash)
      redis.hmset(key, *args.last.inject([]) do |memo,kv|
        memo + [kv[0], marshal(kv[1], options[:marshal_keys][kv[0]])]
      end)
    end
    alias_method :update, :bulk_set

    def fill(pairs={})
      raise ArgumentError, "Arugment to fill must be a hash of key/value pairs" unless pairs.is_a?(::Hash)
      pairs.each do |field, value|
        redis.hsetnx(key, field, marshal(value, options[:marshal_keys][field]))
      end
    end

    def bulk_get(*fields)
      hsh = {}
      res = redis.hmget(key, *fields.flatten)
      fields.each do |k|
        hsh[k] = unmarshal(res.shift, options[:marshal_keys][k])
      end
      hsh
    end

    def bulk_values(*keys)
      res = redis.hmget(key, *keys.flatten)
      keys.inject([]){|collection, k| collection << unmarshal(res.shift, options[:marshal_keys][k])}
    end

    def increment(field, by=1)
      ret = redis.hincrby(key, field, by)
      unless ret.is_a? Array
        ret.to_i
      else
        nil
      end
    end

    def decrement(field, by=1)
      increment(field, -by)
    end

    def increment_by_float(field, by=1.0)
      ret = redis.hincrbyfloat(key, field, by)
      unless ret.is_a? Array
        ret.to_i
      else
        nil
      end
    end

    def decrement_by_float(field, by=1.0)
      incrbyfloat(field, -by)
    end

    expiration_filter :[]=, :bulk_set, :update, :fill, :increment, :increment_by_float
  end
end