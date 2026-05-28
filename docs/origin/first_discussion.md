# FieldStruct — original idea

*The first design notes for FieldStruct, kept for historical context and lightly tidied for readability. The ideas and intent are unchanged.*

## The core idea

I want to build a Ruby library for POROs whose attributes have enforced, validatable types.

You define a class where each attribute (a *field*) is declared with a name, a type, and options that customize that type. The collected field definitions form a class-level **metadata** object that can be inspected and introspected. From a field's type and options, the library knows how to import and export that field's name/value pair. From the class metadata, the class can:

- generate a new instance,
- check a value's type validity and produce a list of errors,
- emit RBS/Sorbet type information for static type checking.

The library ships basic types — String, Integer, Float, Date, Time, etc. — each a class supporting basic methods to import and export a value.

The library is named **FieldStruct**.

## Types live in a collection

Type instances live in a type collection:

```ruby
TypeCollection.register :integer, IntegerType, **options
```

The library provides a base collection that holds all of its base types:

```ruby
class FieldStruct
  def self.field_types
    @field_types ||= TypeCollection.new
  end
end
```

Other namespaces can start their own collection or extend the base one. A class in a namespace walks its own namespace outward to find the types available to it, defaulting to the base collection.

## Defining a class

A plain Ruby class gains the FieldStruct features by inheriting from `FieldStruct::Base`:

```ruby
class User < FieldStruct::Base
  required :username, :string, default: "username"
end

class FullUsername < User
  field :email, :string, required: false, format: some_email_regexp
end
```

`User` has a single attribute, `username`; `FullUsername` has two, `username` and `email`. Required fields must hold a value the type recognizes as *present*; optional (non-required) fields skip that check. Some field definitions run specialized validations, such as a string matching a regexp format.

FieldStruct classes are themselves types.

## RBS integration

- Build a generator that introspects `FieldStruct::Metadata` and dynamically outputs an RBS file for static typing.
- Implement the export interface so that `FullUser.new(...).export` produces a clean, serialized hash, handling nested instances correctly.

## JSON integration

Implement a JSON importer and exporter.

## Aliases

Implement aliases so we can:

- import an `EmailAddress` as a value into an `:email` attribute;
- export a matching hash back to the original hash/JSON — with options to export using either the aliased or the native attribute names;
- use getters and setters for both the original and the aliased attributes.

## Coercion on assignment

Setters must coerce after initialization, not only at construction time — make sure this holds.

## Implementation notes

We want to:

- implement all the basic types that Rails' `ActiveModel` provides, without reusing its code;
- ensure the implementation is performant and memory-efficient;
- provide clear, concise documentation for each feature;
- write unit tests for all implemented features;
- use YARD for documentation — each method describes its purpose, parameters, and return values as far as possible;
- use RSpec for testing;
- use RuboCop for linting;
- use SimpleCov for code coverage;
- use [Sord](https://github.com/AaronC81/sord) to generate RBS and Sorbet type stubs automatically;
- keep to a single file;
- keep all the original design conversations in `docs/origin/`;
- document all implemented features in `docs/features/`.
