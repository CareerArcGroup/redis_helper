class Redis
  class Counter < Redis::RedisObject
    include Redis::RedisHelper::CoreCommands
    attr_reader :key, :options

    def initialize(key, *args)
      super(key, *args)

      # counters are a native concept to redis, so
      # we can't support marshalling here...
      raise ArgumentError, "Marshalling redis counters does not compute" if @options[:marshal]

      @options[:start] ||= @options[:default] || 0
      redis.setnx(key, @options[:start]) unless @options[:start] == 0 || @options[:init] === false
    end

    def reset(to=options[:start])
      redis.set key, to.to_i; true
    end

    def get_set(to=options[:start])
      redis.getset(key, to.to_i).to_i
    end

    def value
      redis.get(key).to_i
    end

    def value=(val)
      val.present? ? redis.set(key, val) : delete!
    end

    def to_f
      redis.get(key).to_f
    end

    def increment(by=1, &block)
      float = by.is_a? Float
      result = redis.public_send(float ? :incrbyfloat : :incrby, key, by)
      val = float ? result.to_f : result.to_i
      block_given? ? rewindable_block(:decrement, by, val, &block) : val
    end

    def decrement(by=1, &block)
      float = by.is_a? Float
      result = redis.public_send(float ? :decrbyfloat : :decrby, key, by)
      val = float ? result.to_f : result.to_i
      block_given? ? rewindable_block(:increment, by, val, &block) : val
    end

    def to_s; value.to_s; end
    def nil?; value.nil? end
    alias_method :to_i, :value

    %w(== < > <= >=).each do |m|
      class_eval <<-EndOverload
        def #{m}(x)
          value #{m} x
        end
      EndOverload
    end

    expiration_filter :increment, :decrement

    private

    def rewindable_block(rewind, by, value, &block)
      raise ArgumentError, "Missing block to rewindable_block" unless block_given?
      ret = nil
      begin
        ret = yield value
      rescue
        send(rewind, by)
        raise
      end
      send(rewind, by) if ret.nil?
      ret
    end
  end
end