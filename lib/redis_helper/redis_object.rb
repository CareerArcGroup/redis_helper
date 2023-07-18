class Redis
  class RedisObject
    MethodSuffixChars = ['=', '?', '!']

    def initialize(key, *args)
      @key = key.is_a?(Array) ? key.flatten.join(':') : key
      @options = args.last.is_a?(Hash) ? args.pop : {}
      @redis = args.first
    end

    def redis
      @redis || ::Redis::RedisHelper.redis
    end

    def set_expiration
      return unless redis.ttl(key) < 0

      if (expiration = options[:expiration])
        redis.expire(key, expiration)
      elsif (expire_at = options[:expire_at])
        at = expire_at.respond_to?(:call) ? expire_at.call : expire_at
        redis.expireat(key, at.to_i) if at
      end
    end

    def self.expiration_filter(*names)
      names.each do |name|
        has_suffix = MethodSuffixChars.include? name.to_s[-1]
        base_name = has_suffix ? name[0..-2] : name
        suffix = has_suffix ? name[-1] : ''

        with_name = "#{base_name}_with_expiration#{suffix}".to_sym
        without_name = "#{base_name}_without_expiration#{suffix}".to_sym

        alias_method without_name, name

        define_method(with_name) do |*args, **kwargs|
          result = send(without_name, *args, **kwargs)
          set_expiration
          result
        end

        alias_method name, with_name
      end
    end
  end
end
