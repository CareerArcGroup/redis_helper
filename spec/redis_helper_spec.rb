require 'test_helper'
require 'yaml'

describe Redis::RedisHelper do
  before(:all) do
    config_path = "redis.yml"

    if File.exist?(config_path)
      Redis::RedisHelper.redis = Redis.new(YAML.load(File.read(config_path)))
    else
      puts "No redis.yml file found in root directory, using default connection settings..."
      Redis::RedisHelper.redis = Redis.new
    end

    class Redis::RedisBackedObject
      include Redis::RedisHelper

      # all redis-backed object must
      # define a (unique) id property
      def id; 42 end

      value :first_name
      value :updated_at, :marshal => true
      value :key_location, :expiration => 10
      value :milk, :expire_at => Time.now + 100
      value :current_galaxy, :global => true
      counter :num_grapes
      list :shopping_list, :marshal => true
      set :numbers, :marshal => true
      sorted_set :high_scores
    end

    @obj = Redis::RedisBackedObject.new
  end

  describe 'A redis-backed object' do
    describe 'A simple value property' do
      it 'should store the value in redis' do
        key = @obj.first_name.key
        @obj.first_name = "John"

        expect(Redis::RedisHelper.redis.get(key)).to eq "John"
      end

      it 'should retrieve the value from redis' do
        key = @obj.first_name.key
        Redis::RedisHelper.redis.set(key, 'Randall')

        expect(@obj.first_name).to eq "Randall"
      end

      it 'should handle nil values' do
        @obj.first_name = 'Lorax'
        expect(@obj.first_name).to eq "Lorax"

        @obj.first_name = nil
        expect(@obj.first_name).to be_nil
      end

      it 'should handle class variables' do
        Redis::RedisBackedObject.current_galaxy = "Milky Way"
        expect(Redis::RedisBackedObject.current_galaxy).to eq "Milky Way"
      end

      it 'should marshal objects when configured to do so' do
        @obj.updated_at = Time.now
        expect(@obj.updated_at.value.class).to eq Time
      end

      it 'should respect value expiration (absolute)' do
        @obj.milk = 'Yummy'

        expect(@obj.milk).to eq 'Yummy'
        expect(@obj.milk.ttl).to be > 0
        expect(@obj.milk.ttl).to be <= 100
      end

      it 'should respect value expiration (relative)' do
        @obj.key_location = 'On my desk'

        expect(@obj.key_location).to eq 'On my desk'
        expect(@obj.key_location.ttl).to be > 0
        expect(@obj.key_location.ttl).to be <= 10
      end

      it 'should support counters' do
        @obj.num_grapes.reset
        expect(@obj.num_grapes).to eq 0
        expect(@obj.num_grapes.increment).to eq 1
        expect(@obj.num_grapes).to eq 1
        expect(@obj.num_grapes.decrement).to eq 0
        expect(@obj.num_grapes).to eq 0
      end
    end

    describe 'A list property' do
      it 'should handle lists of simple values' do
        @obj.shopping_list.clear!

        expect(@obj.shopping_list).to be_empty

        @obj.shopping_list << 'zebras'

        expect(@obj.shopping_list).to eq %w(zebras)

        @obj.shopping_list.clear!

        expect(@obj.shopping_list).to be_empty

        @obj.shopping_list << 'apples'

        expect(@obj.shopping_list).to eq %w(apples)

        @obj.shopping_list.unshift 'bananas'

        expect(@obj.shopping_list.to_s).to eq 'bananas, apples'
        expect(@obj.shopping_list).to eq %w(bananas apples)

        @obj.shopping_list.push 'cucumbers'

        expect(@obj.shopping_list).to eq %w(bananas apples cucumbers)
        expect(@obj.shopping_list.first).to eq 'bananas'
        expect(@obj.shopping_list.last).to eq 'cucumbers'

        @obj.shopping_list << 'durian'

        expect(@obj.shopping_list).to eq %w(bananas apples cucumbers durian)
        expect(@obj.shopping_list[0]).to eq 'bananas'
        expect(@obj.shopping_list[1]).to eq 'apples'
        expect(@obj.shopping_list[2]).to eq 'cucumbers'
        expect(@obj.shopping_list[3]).to eq 'durian'

        expect(@obj.shopping_list.include?('cucumbers')).to be true
        expect(@obj.shopping_list.include?('eggplant')).to be false

        expect(@obj.shopping_list.pop).to eq 'durian'
        expect(@obj.shopping_list[0]).to eq @obj.shopping_list.at(0)
        expect(@obj.shopping_list[1]).to eq @obj.shopping_list.at(1)
        expect(@obj.shopping_list[2]).to eq @obj.shopping_list.at(2)
        expect(@obj.shopping_list).to eq %w(bananas apples cucumbers)

        expect(@obj.shopping_list.shift).to eq 'bananas'
        expect(@obj.shopping_list).to eq ['apples', 'cucumbers']

        @obj.shopping_list << 'eggplant' << 'figs' << 'eggplant'

        expect(@obj.shopping_list).to eq %w(apples cucumbers eggplant figs eggplant)
        expect(@obj.shopping_list.delete!('eggplant')).to eq 2
        expect(@obj.shopping_list).to eq %w(apples cucumbers figs)

        @obj.shopping_list << 'grapes'

        expect(@obj.shopping_list).to eq %w(apples cucumbers figs grapes)
        expect(@obj.shopping_list[0..2]).to eq %w(apples cucumbers figs)
        expect(@obj.shopping_list[1, 3]).to eq %w(cucumbers figs grapes)
        expect(@obj.shopping_list.length).to eq 4
        expect(@obj.shopping_list.size).to eq 4

        @obj.shopping_list.push('habaneros', 'illy')

        expect(@obj.shopping_list).to eq %w(apples cucumbers figs grapes habaneros illy)

        i = -1
        @obj.shopping_list.each do |item|
          expect(item).to eq @obj.shopping_list[i += 1]
        end

        @obj.shopping_list.each_with_index do |item,i|
          expect(item).to eq @obj.shopping_list[i]
        end

        coll = @obj.shopping_list.collect {|item| item}
        expect(coll).to eq %w(apples cucumbers figs grapes habaneros illy)

        @obj.shopping_list << 'apples'
        coll = @obj.shopping_list.select {|item| item == 'apples'}
        expect(coll).to eq %w(apples apples)
      end
    end

    describe 'A set property' do
      it 'should return random members' do
        numbers = [1, 2, 3, 4, 5]

        @obj.numbers.clear!

        expect(@obj.numbers.random_member).to be_nil
        expect(@obj.numbers.random_member(3)).to eq([])

        @obj.numbers.merge(numbers)

        expect(numbers).to include(@obj.numbers.random_member)
        expect(@obj.numbers.random_member(3).size).to eq(3)
      end
    end

    describe 'A sorted set property' do
      it 'should handle sorted sets of somple values' do
        @obj.high_scores.clear!

        expect(@obj.high_scores).to_not include('Stephen')
        expect(@obj.high_scores).to be_empty

        @obj.high_scores['Stephen'] = 9000

        expect(@obj.high_scores).to include('Stephen')
        expect(@obj.high_scores.score('Stephen')).to eq 9000
        expect(@obj.high_scores.size).to eq 1

        @obj.high_scores.add('Patrick', -1000000)

        expect(@obj.high_scores['Patrick']).to eq(-1000000)

        @obj.high_scores['Hodor'] = 400
        @obj.high_scores['John Snow'] = 500
        @obj.high_scores['Ygritte'] = 100
        @obj.high_scores['Bill'] = -200
        @obj.high_scores['Sam'] = -5000

        expect(@obj.high_scores.size).to be 7
        expect(@obj.high_scores.range_by_score(0, 600).size).to eq 3
        expect(@obj.high_scores.range_by_score(-200, 100).size).to eq 2
        expect(@obj.high_scores.range_by_score('-inf', 0).size).to eq 3
      end
    end
  end
end
