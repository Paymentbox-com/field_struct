# FieldStruct

## First idea

I’m interested in building a Ruby library to build POROs that have attributes that have enforced types that can be validated.
The basic idea is you define a class where each attribute (field) is defined with a name, a type and and options to customize that type. The collection of field definitions produce a metadata object as a class level object that can be inspected and introspected. A field can use its type and options to provide information on how to import and export its name and value tuple. And the class metadata object can help in generating a new instance of that class, check its type validity and produce a list of errors if present, and provide RBS/Sorbet type information for static type checking.
The library would provide basic types like String, Integer, Float, Date, Time, etc. These types would be classes that support basic method to import and export a value.
The name of this library would be FieldStruct.

## More details #1

Should have mentioned that type instances live in a Type collection. Like:

```ruby
TypeCollection.register :integer, IntegerType, **options
```

The library provides a base type collection where all its base types are collected as:

```ruby
class FieldStruct
  def self. field_types
    @field_types ||= TypeCollection.new
  end
end
```

And other namespaces can initiate their own collection or extend the base collection. So a class in a namespace would travel its own namespace down to find the types it had available or default to the base types collection.

A basic Ruby class would obtain the FS features by inheriting from the FieldStruct::Base class.

```ruby
class User < FieldStruct:: Base
  required :username, : string, default: “username”
end

class FullUsername < Username
  field :email, :string, required: false, format: some_email_regexp
end
```

A User has a single attribute: username. But a FullUsername has two attributes: username and email. Required fields need to have a value that the type would recognize as present. Optional, not required, fields don’t have that validation check. Some field definitions can run specialized validations line a string matching a regexp format.

Also FS classes are types themselves

## RBS integration

How can we build a generator that introspects the FieldStruct::Metadata and dynamically outputs an RBS file for static typing?

Show me how we would implement the export interface so that FullUser.new(...).export produces a clean, serialized hash, handling the nested instances correctly.

## JSON integration

Implement a JSON importer and exporter

## Aliases

Implement aliases so:
- we can import an “EmailAddress” as a value to an :email attribute
- we can export a matching hash to the original hash/json - provide options to export using the aliased or native attribute names
- have getter/setters for both original and aliased attributes

## More notes

Do setters coerce after initialization? We need to make sure we do.

## Notes on implementation

We want to: 
- implement all the basic types that Rails' `ActiveModel` implements without reusing their code.
- ensure that the implementation is performant and memory-efficient
- provide clear and concise documentation for each feature
- write unit tests for all implemented features
- we use YARD for documentation and each method provides, as far as possible, a clear description of its purpose, parameters, and return values.
- we use RSpec for testing
- we use Rubocop for linting
- we use SimpleCov for code coverage
- we use [Sord](https://github.com/AaronC81/sord) to provide RBS and Sorbet types stubs automatically
- we keep a simgle file
- keep all the original design conversations in the docs/origin/ directory
- document all implemented features in the docs/features/ directory

