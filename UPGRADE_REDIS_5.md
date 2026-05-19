# Redis-rb 5.0.0 Upgrade - Breaking Changes Analysis

This document outlines what would break in the `redis_helper` codebase when upgrading from `redis ~> 4.0` to `redis >= 5.0.0`, and provides solutions for each issue.

---

## 1. `sadd` and `srem` Now Always Return an Integer (not a Boolean)

**Affected files:** `lib/redis_helper/set.rb`

**What breaks:**
- `Set#add` (line 13-14) calls `redis.sadd` — in Redis 4.x with a single value, this returned a Boolean (`true`/`false`). In 5.0.0 it always returns an Integer.
- `Set#delete` (line 43) calls `redis.srem` — same issue, now returns Integer instead of Boolean.
- `Set#delete_if` (line 46-54) assigns the result of `redis.srem` to `res` and returns it. Code that relies on this being a truthy Boolean may behave unexpectedly (though integers are truthy in Ruby, so this is low-risk).
- `Set#member?` (line 38) uses `redis.sismember` which still returns Boolean, so it's fine.

**Solutions:**
- **Option A (Recommended):** Use the new `sadd?` and `srem?` methods introduced in Redis 4.8+ which explicitly return Booleans. Replace `redis.sadd` with `redis.sadd?` where Boolean semantics are desired (e.g., `delete_if`), and keep `redis.sadd` where the integer count is acceptable or expected.
- **Option B:** Cast results explicitly: `redis.sadd(...) > 0` where a Boolean is needed.

---

## 2. `Redis.new` Raises on Unknown Options

**Affected files:** Any consumer code passing options to `Redis.new`

**What breaks:** In Redis 5.0.0, `Redis.new` will raise an error if provided with unknown options. The library itself doesn't call `Redis.new` with options (that's left to the consumer), but consumers upgrading may need to audit their initialization code.

**What was removed:**
- `:logger` option
- `:reconnect_delay_max` and `:reconnect_delay` options
- `:synchrony` driver

**Solutions:**
- **Option A (Recommended):** Remove any unsupported options from `Redis.new` calls. For logging, use external instrumentation. For reconnection, pass precise sleep durations to `reconnect_attempts` instead.
- **Option B:** No changes needed in this library itself, but document the requirement for consumers.

---

## 3. `Redis.current` Removed

**Affected files:** None directly in this library.

**What breaks:** This library does NOT use `Redis.current`. It already uses its own connection management pattern (`RedisHelper.redis=` / `RedisHelper.redis`), which is exactly the pattern Redis 5.0.0 recommends. **No changes needed for this issue.**

---

## 4. Default Timeout Decreased from 5 seconds to 1 second

**Affected files:** `lib/redis_helper/lock.rb`

**What breaks:** The `Lock` class uses a default timeout of 5 seconds (`@options[:timeout] ||= 5`) for acquiring locks. While this is the lock acquisition timeout (not the Redis connection timeout), consumers using the default `Redis.new` connection may experience more `Redis::TimeoutError` exceptions if their Redis server is slow, because the *connection* timeout drops from 5s to 1s.

**Solutions:**
- **Option A (Recommended):** Document the timeout change for consumers. They can pass `timeout: 5` to `Redis.new` to restore old behavior.
- **Option B:** No code changes needed in this library — this affects Redis connection configuration, not library logic.

---

## 5. `pipelined` and `multi` Signature Changes

**Affected files:** None directly — this library does not use `pipelined` or `multi` internally.

**What breaks:** In Redis 5.0.0, commands inside `pipelined` and `multi` blocks MUST be called on the block argument, not the original redis instance. This library doesn't use these methods, but consumers who combine `redis_helper` objects with pipeline/multi blocks may be affected.

**Solutions:**
- **Option A:** No changes needed in library code.
- **Option B (Enhancement):** Consider adding pipeline/transaction support to the library's objects in the future.

---

## 6. `getset` is Deprecated (used in Counter and Lock)

**Affected files:** `lib/redis_helper/counter.rb` (line 22), `lib/redis_helper/lock.rb` (line 55)

**What breaks:** While `getset` still works in Redis 5.x, it has been deprecated at the Redis server level since Redis 6.2 in favor of `SET` with `GET` option. This won't break immediately but should be addressed for forward compatibility.

**Solutions:**
- **Option A (Recommended):** Replace `redis.getset(key, value)` with `redis.set(key, value, get: true)` which returns the old value.
- **Option B:** Leave as-is for now since `getset` still works, and address in a future PR targeting Redis 7+ server compatibility.

---

## 7. Gemspec Dependency Version Constraint

**Affected file:** `redis_helper.gemspec` (line 30)

**What breaks:** The current constraint `"~> 4.0"` explicitly prevents installing redis-rb 5.x.

**Solutions:**
- **Option A (Recommended):** Change to `">= 4.6", "< 6"` to support both Redis 4.6+ (which has deprecation warnings and `sadd?`/`srem?`) and Redis 5.x. This gives consumers flexibility during migration.
- **Option B:** Change to `"~> 5.0"` to require Redis 5.x, dropping Redis 4.x support entirely.
- **Option C:** Change to `">= 5.0", "< 6"` to require at least Redis 5.0.0.

---

## 8. `hmset` is Deprecated

**Affected file:** `lib/redis_helper/hash_set.rb` (line 82)

**What breaks:** `hmset` was deprecated in Redis 4.0.0 at the server level in favor of variadic `hset`. While it still works, it may be removed in a future redis-rb version.

**Solutions:**
- **Option A (Recommended):** Replace `redis.hmset(key, *pairs)` with `redis.hset(key, *pairs)` — the variadic `hset` accepts the same field-value format.
- **Option B:** Leave as-is since it still works, but plan for future deprecation.

---

## 9. `rpoplpush` Deprecated in Favor of `lmove`

**Affected file:** `lib/redis_helper/list.rb` (line 50)

**What breaks:** `rpoplpush` was deprecated at the Redis server level in Redis 6.2 in favor of `LMOVE`. While it still works in redis-rb 5.x, it should be updated for forward-compatibility.

**Solutions:**
- **Option A (Recommended):** Replace `redis.rpoplpush(src, dst)` with `redis.lmove(src, dst, "RIGHT", "LEFT")`.
- **Option B:** Leave as-is for now since it still functions correctly.

---

## Summary of Required Changes (Minimum for 5.0.0 Compatibility)

| Priority | File | Change |
|----------|------|--------|
| **Required** | `redis_helper.gemspec` | Update version constraint to allow redis 5.x |
| **Required** | `lib/redis_helper/set.rb` | Handle `sadd`/`srem` returning Integer instead of Boolean |
| Low Risk | `lib/redis_helper/counter.rb` | Consider replacing `getset` with `set(..., get: true)` |
| Low Risk | `lib/redis_helper/lock.rb` | Consider replacing `getset` with `set(..., get: true)` |
| Low Risk | `lib/redis_helper/hash_set.rb` | Consider replacing `hmset` with variadic `hset` |
| Low Risk | `lib/redis_helper/list.rb` | Consider replacing `rpoplpush` with `lmove` |

The good news is that this library already follows the recommended pattern for Redis connection management (explicit instance passing rather than `Redis.current`), so the biggest breaking change in Redis 5.0.0 does not affect this codebase at all.
