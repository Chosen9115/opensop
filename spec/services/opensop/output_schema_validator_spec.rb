require 'rails_helper'

RSpec.describe Opensop::OutputSchemaValidator do
  describe "#validate / #validate!" do
    context "happy path: scalars with numeric coercion" do
      let(:schema) do
        {
          "name" => "string",
          "score" => "number",
          "active" => "boolean"
        }
      end

      it "passes JSON-native scalars through unchanged" do
        validator = described_class.new(schema)
        ok, errors, coerced = validator.validate(
          { "name" => "alice", "score" => 0.92, "active" => true }
        )
        expect(ok).to be true
        expect(errors).to be_empty
        expect(coerced).to eq("name" => "alice", "score" => 0.92, "active" => true)
      end

      it "coerces numeric strings to Float / Integer" do
        validator = described_class.new(schema)
        coerced = validator.validate!(
          { "name" => "bob", "score" => "0.42", "active" => false }
        )
        expect(coerced["score"]).to eq(0.42)
        expect(coerced["score"]).to be_a(Float)

        coerced2 = validator.validate!(
          { "name" => "bob", "score" => "7", "active" => false }
        )
        expect(coerced2["score"]).to eq(7)
        expect(coerced2["score"]).to be_a(Integer)
      end

      it "rejects non-numeric values for number fields" do
        validator = described_class.new(schema)
        ok, errors, _ = validator.validate(
          { "name" => "n", "score" => "high", "active" => true }
        )
        expect(ok).to be false
        expect(errors).to include(a_string_matching(/score: expected number, got "high"/))
      end

      it "does NOT coerce strings to booleans" do
        validator = described_class.new(schema)
        ok, errors, _ = validator.validate(
          { "name" => "n", "score" => 1, "active" => "true" }
        )
        expect(ok).to be false
        expect(errors).to include(a_string_matching(/active: expected boolean/))
      end
    end

    context "enum mismatch" do
      let(:schema) { { "intent" => "enum[question, task, complaint]" } }

      it "validates a matching enum value" do
        validator = described_class.new(schema)
        expect(validator.validate!({ "intent" => "task" })).to eq("intent" => "task")
      end

      it "errors with path on mismatch" do
        validator = described_class.new(schema)
        ok, errors, _ = validator.validate({ "intent" => "smalltalk" })
        expect(ok).to be false
        expect(errors).to include(
          a_string_matching(/\Aintent: expected one of \["question", "task", "complaint"\], got "smalltalk"\z/)
        )
      end

      it "is case-sensitive" do
        validator = described_class.new(schema)
        ok, _errors, _ = validator.validate({ "intent" => "Task" })
        expect(ok).to be false
      end
    end

    context "nested object validation" do
      let(:schema) do
        {
          "intent" => "enum[question, task, complaint]",
          "confidence" => "number",
          "nested" => {
            "flag" => "boolean",
            "tags" => "array[string]"
          }
        }
      end

      it "validates nested fields" do
        validator = described_class.new(schema)
        coerced = validator.validate!(
          {
            "intent" => "question",
            "confidence" => 0.92,
            "nested" => { "flag" => true, "tags" => ["foo", "bar"] }
          }
        )
        expect(coerced["nested"]).to eq("flag" => true, "tags" => ["foo", "bar"])
      end

      it "produces dotted paths for nested errors" do
        validator = described_class.new(schema)
        ok, errors, _ = validator.validate(
          {
            "intent" => "question",
            "confidence" => 0.92,
            "nested" => { "flag" => "yes", "tags" => ["foo", 42] }
          }
        )
        expect(ok).to be false
        expect(errors).to include(a_string_matching(/\Anested\.flag: expected boolean/))
        expect(errors).to include(a_string_matching(/\Anested\.tags\[1\]: expected string, got 42\z/))
      end

      it "errors when a nested object is missing entirely" do
        validator = described_class.new(schema)
        ok, errors, _ = validator.validate(
          { "intent" => "question", "confidence" => 0.92 }
        )
        expect(ok).to be false
        expect(errors).to include(a_string_matching(/\Anested: missing required key\z/))
      end
    end

    context "arrays" do
      it "validates an array of strings" do
        validator = described_class.new("tags" => "array[string]")
        coerced = validator.validate!("tags" => ["a", "b", "c"])
        expect(coerced).to eq("tags" => ["a", "b", "c"])
      end

      it "errors on the offending index for a bad element" do
        validator = described_class.new("tags" => "array[string]")
        ok, errors, _ = validator.validate("tags" => ["a", 42, "c"])
        expect(ok).to be false
        expect(errors).to eq(["tags[1]: expected string, got 42"])
      end

      it "validates an array of nested objects via the [<hash>] form" do
        schema = {
          "items" => [
            {
              "label" => "string",
              "score" => "number"
            }
          ]
        }
        validator = described_class.new(schema)
        coerced = validator.validate!(
          "items" => [
            { "label" => "a", "score" => 1 },
            { "label" => "b", "score" => "0.5" }
          ]
        )
        expect(coerced["items"][0]).to eq("label" => "a", "score" => 1)
        expect(coerced["items"][1]).to eq("label" => "b", "score" => 0.5)
      end

      it "reports per-item errors with bracketed paths in arrays of objects" do
        schema = { "items" => [{ "label" => "string", "score" => "number" }] }
        validator = described_class.new(schema)
        ok, errors, _ = validator.validate(
          "items" => [
            { "label" => "a", "score" => 1 },
            { "label" => 7, "score" => "oops" }
          ]
        )
        expect(ok).to be false
        expect(errors).to include(a_string_matching(/\Aitems\[1\]\.label: expected string, got 7\z/))
        expect(errors).to include(a_string_matching(/\Aitems\[1\]\.score: expected number, got "oops"\z/))
      end
    end

    context "missing required keys" do
      it "reports each missing key" do
        validator = described_class.new(
          "a" => "string",
          "b" => "number",
          "c" => "boolean"
        )
        ok, errors, _ = validator.validate({})
        expect(ok).to be false
        expect(errors).to contain_exactly(
          "a: missing required key",
          "b: missing required key",
          "c: missing required key"
        )
      end

      it "raises Invalid with errors attr from validate!" do
        validator = described_class.new("a" => "string")
        expect { validator.validate!({}) }
          .to raise_error(described_class::Invalid) do |e|
            expect(e.errors).to eq(["a: missing required key"])
          end
      end
    end

    context "extra unknown keys" do
      it "preserves extra keys silently" do
        validator = described_class.new("intent" => "string")
        coerced = validator.validate!(
          "intent" => "question",
          "future_field" => { "anything" => 123 }
        )
        expect(coerced).to eq(
          "intent" => "question",
          "future_field" => { "anything" => 123 }
        )
      end
    end

    context "symbol-keyed input values" do
      it "is tolerant of symbol keys in the input value" do
        validator = described_class.new("intent" => "string")
        expect(validator.validate!(intent: "question")).to eq("intent" => "question")
      end
    end

    context "schema authoring errors" do
      it "raises SchemaError for an unknown type expression" do
        expect { described_class.new("foo" => "decimal") }
          .to raise_error(described_class::SchemaError, /foo: unknown type expression "decimal"/)
      end

      it "raises SchemaError for a malformed array expression" do
        expect { described_class.new("xs" => "array[]") }
          .to raise_error(described_class::SchemaError, /unknown type expression/)
      end

      it "raises SchemaError for an empty enum" do
        expect { described_class.new("e" => "enum[]") }
          .to raise_error(described_class::SchemaError, /unknown type expression/)
      end

      it "raises SchemaError when the schema itself is not a Hash" do
        expect { described_class.new("string") }
          .to raise_error(described_class::SchemaError, /must be a Hash/)
      end

      it "raises SchemaError when an array literal has more than one element" do
        expect {
          described_class.new(
            "items" => [{ "a" => "string" }, { "b" => "string" }]
          )
        }.to raise_error(described_class::SchemaError, /array literal must have exactly one element/)
      end
    end

    context "top-level shape errors" do
      it "errors when input is not an object at all" do
        validator = described_class.new("a" => "string")
        ok, errors, _ = validator.validate("not a hash")
        expect(ok).to be false
        expect(errors.first).to match(/\(root\): expected object, got "not a hash"/)
      end
    end
  end
end
