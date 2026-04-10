# frozen_string_literal: true

require "spec_helper"

# Exhaustive PII masking safety tests.
# These verify the "safe default" behaviour for every classification × role combination.
RSpec.describe "PII masking safety", :db do
  let(:registry) { SpecSupport.build_registry }
  let(:masker)   { Flehmen::Presentation::Masker.new }

  def build_fd(classification, mask: nil)
    Flehmen::Catalog::FieldDefinition.new(:test_field, classification: classification, mask: mask)
  end

  shared_examples "always visible" do |classification|
    let(:field_def) { { test_field: build_fd(classification) } }

    it "is visible for support" do
      result = masker.mask({ "test_field" => "value" }, field_def, :support)
      expect(result["test_field"]).to eq("value")
    end

    it "is visible for admin" do
      result = masker.mask({ "test_field" => "value" }, field_def, :admin)
      expect(result["test_field"]).to eq("value")
    end
  end

  shared_examples "masked for non-admin, visible for admin" do |classification|
    let(:field_def) { { test_field: build_fd(classification) } }

    it "is masked for support" do
      result = masker.mask({ "test_field" => "sensitive_value" }, field_def, :support)
      expect(result["test_field"]).not_to eq("sensitive_value")
    end

    it "is visible for admin" do
      result = masker.mask({ "test_field" => "sensitive_value" }, field_def, :admin)
      expect(result["test_field"]).to eq("sensitive_value")
    end
  end

  shared_examples "always [FILTERED]" do |classification|
    let(:field_def) { { test_field: build_fd(classification) } }

    it "is [FILTERED] for support" do
      result = masker.mask({ "test_field" => "secret" }, field_def, :support)
      expect(result["test_field"]).to eq("[FILTERED]")
    end

    it "is [FILTERED] even for admin" do
      result = masker.mask({ "test_field" => "secret" }, field_def, :admin)
      expect(result["test_field"]).to eq("[FILTERED]")
    end
  end

  shared_examples "always excluded" do |classification|
    let(:field_def) { { test_field: build_fd(classification) } }

    it "is excluded from output for support" do
      result = masker.mask({ "test_field" => "restricted" }, field_def, :support)
      expect(result).not_to have_key("test_field")
    end

    it "is excluded from output for admin" do
      result = masker.mask({ "test_field" => "restricted" }, field_def, :admin)
      expect(result).not_to have_key("test_field")
    end
  end

  describe ":public classification"    do include_examples "always visible",   :public end
  describe ":internal classification"  do include_examples "always visible",   :internal end
  describe ":personal classification"  do include_examples "masked for non-admin, visible for admin", :personal end
  describe ":sensitive classification" do include_examples "always [FILTERED]", :sensitive end
  describe ":restricted classification" do include_examples "always excluded",  :restricted end

  describe "undeclared fields (no FieldDefinition)" do
    it "defaults to [FILTERED] for support (safe side)" do
      result = masker.mask({ "unknown" => "data" }, {}, :support)
      expect(result["unknown"]).to eq("[FILTERED]")
    end

    it "passes through for admin" do
      result = masker.mask({ "unknown" => "data" }, {}, :admin)
      expect(result["unknown"]).to eq("data")
    end
  end
end
