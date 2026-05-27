---
layout: home

hero:
  name: FieldStruct
  text: Typed POROs for Ruby.
  tagline: Declared attributes, type coercion, presence checks, and validation — without ActiveModel, without a database, without surprises.
  actions:
    - theme: brand
      text: Get Started
      link: /guide/getting-started
    - theme: alt
      text: View on GitHub
      link: https://github.com/Paymentbox-com/field_struct

features:
  - title: Typed attributes
    details: Declare each field with a type. Inputs are coerced through pluggable Type classes; failures surface as per-field errors instead of stray exceptions deep in your code.
  - title: Real validation
    details: Required fields, format checks, enums, ranges, cross-field rules. Errors live on the instance, keyed by field, refreshed on every assignment.
  - title: Inspectable Metadata
    details: Each class collects its declarations into a Metadata object you can iterate, introspect, and ship to docs / schema generators.
  - title: Composable
    details: Nest FieldStructs inside other FieldStructs. Allow a field to hold any of several types via :union. Serialize the whole tree to JSON.
  - title: Pattern-matching ready
    details: Instances respond to deconstruct / deconstruct_keys, so case/in works on FieldStruct values out of the box.
  - title: Class macros, not config
    details: coercion_policy, immutable!, frozen!, unknown_attributes — opt into the behavior you want, where you want, inherited through the class chain.
---

## At a glance

```ruby
class User < FieldStruct::Base
  required :name,  :string,  description: 'Display name'
  required :email, :string,  format: /@/
  optional :age,   :integer, default: 0
end

user = User.new(name: 'Alice', email: 'alice@example.com', age: '30')
user.age           # => 30   (coerced from "30")
user.valid?        # => true
user.attributes    # => { name: 'Alice', email: 'alice@example.com', age: 30 }
user.as_json       # => { name: 'Alice', email: 'alice@example.com', age: 30 }
```

## Why FieldStruct?

`Struct` doesn't coerce or validate. `OpenStruct` is a property bag. `ActiveModel::Attributes` ties you to ActiveSupport and Rails. `dry-struct` has a learning curve and a different cultural style.

FieldStruct sits in the middle: **plain Ruby, ActiveModel-shaped interface, but reuses no AM code**. It's a focused library for the part of your domain that has shape — value objects, request bodies, API payloads, configuration — without dragging in a database layer or a form framework.

## Install

```ruby
# Gemfile
gem 'field_struct'
```

```bash
bundle install
```

Or globally:

```bash
gem install field_struct
```

Continue to [Getting Started →](/guide/getting-started)
