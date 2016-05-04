class Redis
  class Lock < Redis::RedisObject
    class LockTimeout < StandardError; end

    attr_reader :key, :options

    def initialize(key, *args)
      super(key, *args)
      @options[:timeout] ||= 5
      @options[:poll_interval] ||= 0.1
    end

    def clear
      redis.del(key)
    end
    alias_method :delete, :clear

    def locked?
      val = redis.get(key)
      !val.nil? && (val.to_f >= Time.now.to_f)
    end

    # attempts to acquire a lock. if the lock is acquired
    # the given block will be executed and the return value
    # of the block will be returned. if the lock is not
    # acquired, the return value will be nil. the behavior
    # of this method may be altered by the options (defaults shown):
    #
    #  timeout: 5 (sec)         # time (in seconds) to wait to acquire a lock before aborting
    #                           # if timeout is 0, the method will immediately return if the lock
    #                           # cannot be acquired.
    #
    #  poll_interval: 0.1 (sec) # time (in seconds) to wait between each check on the lock.
    #
    def lock(options={}, &block)
      acquired = false
      attempted = false
      expiration = nil

      timeout = options[:timeout] || self.timeout
      poll_interval = options[:poll_interval] || self.poll_interval
      non_blocking = timeout == 0
      start = Time.now

      while non_blocking || !attempted || (Time.now - start < timeout)
        attempted = true
        expiration = generate_expiration
        acquired = redis.setnx(key, expiration)

        break if acquired

        # if we're here, the lock has been acquired by someone
        # else, and we haven't elected to fail fast...
        if has_expiration? && redis.get(key).to_f < Time.now.to_f
          if redis.getset(key, generate_expiration).to_f < Time.now.to_f
            acquired = true; break
          end
        end

        break if non_blocking
        sleep poll_interval
      end

      return nil if non_blocking && !acquired
      raise LockTimeout, "Timeout on lock #{key} exceeded #{timeout} sec" unless acquired

      begin
        result = yield
      ensure
        redis.del(key) if no_expiration? || expiration > Time.now.to_f
      end

      result
    end

    def timeout
      @options[:timeout]
    end

    def poll_interval
      @options[:poll_interval]
    end

    def no_expiration?
      @options[:expiration].nil?
    end

    def has_expiration?
      !no_expiration?
    end

    protected

    def generate_expiration
      has_expiration? ? (Time.now + @options[:expiration].to_f + 1).to_f : 1
    end
  end
end