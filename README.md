# Royal

Welcome to your new gem! In this directory, you'll find the files you need to be able to package up your Ruby library into a gem. Put your Ruby code in the file `lib/royal`. To experiment with that code, run `bin/console` for an interactive prompt.

TODO: Delete this and the text above, and describe your gem

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'royal'
```

And then execute:

    $ bundle install

Or install it yourself as:

    $ gem install royal

### Generating Configuration

    $ bin/rails g royal:install

This will place a configuration file at `config/initializers/royal.rb` in your Rails application directory.

### Generating Migrations

    $ bin/rails g royal:migration

    $ bin/rails db:migrate

## Usage

```ruby
class User < ApplicationRecord
  include Royal::Points

  # ...
end
```

Royal uses a separate ledger table to track points for your models, so it's not necessary to add any columns to existing tables.

### Viewing the Point Balance

To view the current balance of a record, use the `current_points` method:

```ruby
user = User.first

user.current_points # => 0
```

**NOTE:** The `current_points` method accesses the database each time it's called.

### Adding Loyalty Points

```ruby
user.add_points(100) # => 100
```

This method returns the new points balance after the operation.

### Spending Loyalty Points

```ruby
user.subtract_points(75) # => 25
```

This method returns the new points balance after the operation.

If the current balance is less than the specified amount of points to subtract, a `Royal::InsufficientPointsError` is raised:

```ruby
user.subtract_points(200) # => raises #<Royal::InsufficientPointsError ...>
```

### Including a Reason or Note

It's possible to include a String of text when adding or subtracting points, which will be stored with the change:

```ruby
user.add_points(50, reason: 'Birthday points!')
```

**NOTE:** By default, the reason can be at most 1000 characters long.

### Linking to Another Record

It's possible to link an additional record when adding or subtracting points.
Below is an example using a hypothetical `Reward` model:

```ruby
reward = Reward.find_by(name: 'Gift Card')

user.subtract_points(50, pointable: reward)
```

### Loyalty Point Balance History

Since points are stored in a ledger, it's possible to view and display the complete history of a points balance:

```erb
<table>
  <tr>
    <th>Operation</th>
    <th>Balance</th>
    <th>Reason</th>
  </tr>
  <% user.point_balances.order(:sequence).each do |point_balance| %>
    <tr>
      <td><%= point_balance.amount.positive? ? 'Added' : 'Spent' %> <%= point_balance.amount %></td>
      <td><%= point_balance.balance %></td>
      <td><%= point_balance.reason %></td>
    </tr>
  <% end %>
</table>
```

**NOTE:** For data integrity reasons, `Royal::PointBalance` records are as marked readonly once persisted to the database.
Modifying or removing existing balance records is not supported.

## Concurrency and Locking

Royal comes with built-in automatic locking around point balance changes.
Since each applicable behaves differently, it also includes a few alternative locking strategies.

Royal supports three possible locking modes:
* Optimistic locking (default)
* Pessimistic locking
* Advisory locking (PosgreSQL only)

Each mode has its own advantages and disadvantages, which are outlined in detail below.
Optimistic locking is used by default and should work well in most use cases and even in high-load applications.
In general, you shouldn't need to change this unless you start to experience `SequenceError`s.

### Optimistic Locking (Default)

This locking mode relies on a unique index specific to `owner` record such that: `(owner_id, owner_type, sequence)`.
A `sequence` column is increased by 1 for every write to the points balance ledger, so any conflicting writes to the table would produce a duplicate value for the `sequence` column and be rejected by the uniqueness constraint.

Whenever an update is rejected by this constraint, the operation is re-attempted with a new sequence value and updated balance calculation.
By default, an update can be re-attempted up to 10 times before a `Royal::SequenceError` is raised.

For most applications, updates should only be very rarely retried and generally resolve it an most one or two attempts.
However, if your application needs to perform frequent, parallel balance updates for a single record, this may become a concern.
(For example, an organization that receives points from all of its employees, or some other group that receives points from all of its members.)

**NOTE:** You shouldn't usually need to change locking strategies unless you see frequent `SequenceError`s or otherwise experience poor performance.
Even in cases where your application does perform a large number of parallel balance updates for the same record, you may see better results changing how your application applies these updates. (e.g. Using a queue to asynchronously apply updatesin sequence from a sepearate task instead of in parallel.)

### Pessimistic Locking

This locking mode relies on row-level exclusive locks acquired on the `owner` record for the points balance.

In general, this strategy is the slowest as it will be blocked by any other locks on the record, and will block all other operations on the record for the duration of the update.
Unless you are experiencing issues with the optimistic locking strategy and are unable to leverage advisory locks for your applicable, use of the strategy is not advised.

### Advisory Locking (PostgreSQL Only)

This locking mode uses an exclusive advisory lock on a key that's unique to each `owner` record via `pg_advisory_xact_lock`.
See more here: https://www.postgresql.org/docs/current/functions-admin.html#FUNCTIONS-ADVISORY-LOCKS

Using advisory locking provides similar advantages to pessimistic locking without having to acquire a row-level lock on the owner record.
Locking is done using the 2-argument version of `pg_advisory_xact_lock` using values computed based from ther `owner` record's ID and polymorphic name.

e.g. A lock for a `User` record with ID 1 would acquire a lock as so:
```sql
SELECT pg_advisory_xact_lock(hashtext('User'), 1)
```

When using advisory locks, there are situations where lock-keys could potentially experience collissions.
Since advisory lock keys are 64-bits wide, it is unlikely to happen for most applications, but is still worth considering.

Two possible situations where these keys would collide are:
1. Your applicable already heavily relies on advisory locks. Note that the single 64-bit argument advisory lock uses a separate key space and does not overlap with the 2-argument key space.
2. Your models have 64-bit (or greater) IDs and the bottom 32-bits are the same. Since the 2 key segments are restricted to 32-bits, this locking system only uses the bottom 32-bits of the `owner` record's ID as part of the lock key.

In most cases, lock-keys colliding would just result in two or more unrelated records waiting before applying a point balance update.
Unless your applicable has a very large number of `owner` records with overlapping keys that are frequently updated together, this shouldn't create any cause for concern.

However, if your application falls into situation #1 described above and also holds advisory locks for extended periods of time, balance updates may stall for much longer than expected as they'll be blocked until the lock is released.

## Future Functionalty and Roadmap

 * [ ] Support multiple types of points per model
 * [ ] Add RSpec matchers to assist in testing
 * [ ] Improve documentation and examples

## Development

After checking out the repo, run `bin/setup` to install dependencies. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/mintyfresh/royal.
