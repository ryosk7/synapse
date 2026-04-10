# frozen_string_literal: true

require "spec_helper"

RSpec.describe Flehmen::Presentation::Masker do
  let(:masker) { described_class.new }

  def build_field_defs(overrides = {})
    defaults = {
      id:        Flehmen::Catalog::FieldDefinition.new(:id,        classification: :public),
      name:      Flehmen::Catalog::FieldDefinition.new(:name,      classification: :personal, mask: :name),
      email:     Flehmen::Catalog::FieldDefinition.new(:email,     classification: :personal, mask: :email),
      phone:     Flehmen::Catalog::FieldDefinition.new(:phone,     classification: :personal, mask: :phone),
      status:    Flehmen::Catalog::FieldDefinition.new(:status,    classification: :public),
      note:      Flehmen::Catalog::FieldDefinition.new(:note,      classification: :internal),
      stripe_id: Flehmen::Catalog::FieldDefinition.new(:stripe_id, classification: :sensitive),
      ssn:       Flehmen::Catalog::FieldDefinition.new(:ssn,       classification: :restricted)
    }
    defaults.merge(overrides)
  end

  let(:attributes) do
    {
      "id"        => 1,
      "name"      => "田中太郎",
      "email"     => "taro@example.com",
      "phone"     => "09012345678",
      "status"    => "active",
      "note"      => "内部メモ",
      "stripe_id" => "cus_abc123",
      "ssn"       => "123-45-6789"
    }
  end

  describe "public fields" do
    it "are always shown regardless of role" do
      result = masker.mask(attributes, build_field_defs, :support)
      expect(result["id"]).to eq(1)
      expect(result["status"]).to eq("active")
    end

    it "are shown for admin too" do
      result = masker.mask(attributes, build_field_defs, :admin)
      expect(result["id"]).to eq(1)
    end
  end

  describe "internal fields" do
    it "are shown for support" do
      result = masker.mask(attributes, build_field_defs, :support)
      expect(result["note"]).to eq("内部メモ")
    end

    it "are shown for admin" do
      result = masker.mask(attributes, build_field_defs, :admin)
      expect(result["note"]).to eq("内部メモ")
    end
  end

  describe "personal fields" do
    it "are partially masked for support (email)" do
      result = masker.mask(attributes, build_field_defs, :support)
      expect(result["email"]).to match(/\*\*\*@example\.com/)
      expect(result["email"]).not_to eq("taro@example.com")
    end

    it "are partially masked for support (phone)" do
      result = masker.mask(attributes, build_field_defs, :support)
      expect(result["phone"]).to match(/\*+\d{4}/)
    end

    it "are partially masked for support (name)" do
      result = masker.mask(attributes, build_field_defs, :support)
      expect(result["name"]).to match(/田\*+/)
    end

    it "are shown in full for admin" do
      result = masker.mask(attributes, build_field_defs, :admin)
      expect(result["email"]).to eq("taro@example.com")
      expect(result["name"]).to eq("田中太郎")
    end
  end

  describe "sensitive fields" do
    it "are always [FILTERED] for support" do
      result = masker.mask(attributes, build_field_defs, :support)
      expect(result["stripe_id"]).to eq("[FILTERED]")
    end

    it "are always [FILTERED] even for admin" do
      result = masker.mask(attributes, build_field_defs, :admin)
      expect(result["stripe_id"]).to eq("[FILTERED]")
    end
  end

  describe "restricted fields" do
    it "are excluded from output for support" do
      result = masker.mask(attributes, build_field_defs, :support)
      expect(result).not_to have_key("ssn")
    end

    it "are excluded from output for admin too (always requires separate process)" do
      result = masker.mask(attributes, build_field_defs, :admin)
      expect(result).not_to have_key("ssn")
    end
  end

  describe "undeclared fields (no FieldDefinition)" do
    it "are [FILTERED] for support (safe default)" do
      attrs    = { "unknown_field" => "secret_value" }
      result   = masker.mask(attrs, {}, :support)
      expect(result["unknown_field"]).to eq("[FILTERED]")
    end

    it "are shown for admin" do
      attrs  = { "unknown_field" => "some_value" }
      result = masker.mask(attrs, {}, :admin)
      expect(result["unknown_field"]).to eq("some_value")
    end
  end

  describe "nil values" do
    it "handles nil value for masked personal field gracefully" do
      attrs   = { "email" => nil }
      result  = masker.mask(attrs, build_field_defs, :support)
      expect(result["email"]).to eq("[FILTERED]")
    end
  end
end
