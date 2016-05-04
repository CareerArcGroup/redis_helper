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
      redis.expire(key, options[:expiration]) if options[:expiration]
      redis.expireat(key, options[:expire_at].to_i) if options[:expire_at]
    end

    def self.expiration_filter(*names)
      names.each do |name|
        has_suffix = MethodSuffixChars.include? name.to_s[-1]
        base_name = has_suffix ? name[0..-2] : name
        suffix = has_suffix ? name[-1] : ''

        with_name = "#{base_name}_with_expiration#{suffix}".to_sym
        without_name = "#{base_name}_without_expiration#{suffix}".to_sym

        alias_method without_name, name

        define_method(with_name) do |*args|
          result = send(without_name, *args)
          set_expiration
          result
        end

        alias_method name, with_name
      end
    end
  end
end