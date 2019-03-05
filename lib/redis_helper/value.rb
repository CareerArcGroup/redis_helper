class Redis
  class Value < Redis::RedisObject
    include Redis::RedisHelper::CoreCommands
    attr_reader :key, :options

    def initialize(key, *args)
      super(key, *args)
      redis.setnx(key, marshal(options[:default])) if options[:default]
    end

    def value=(val)
      val ? redis.set(key, marshal(val)) : delete!
    end

    alias_method :set, :value=

    def value
      unmarshal redis.get(key)
    end

    alias_method :get, :value

    def inspect
      "#<Redis::Value #{value.inspect}>"
    end

    def default_value?; options[:default] && options[:default] == value end
    def ==(other); value == other end
    def nil?; value.nil? end
    def as_json(*args); value.as_json(*args) end
    def to_json(*args); value.to_json(*args) end

    def method_missing(*args)
      self.value.send(*args)
    end

    expiration_filter :value=, :set
  end
end