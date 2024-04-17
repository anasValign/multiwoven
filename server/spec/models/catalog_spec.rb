# frozen_string_literal: true

# == Schema Information
#
# Table name: catalogs
#
#  id           :bigint           not null, primary key
#  workspace_id :integer
#  connector_id :integer
#  catalog      :jsonb
#  catalog_hash :string
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#
require "rails_helper"

RSpec.describe Catalog, type: :model do
  describe "associations" do
    it { should belong_to(:workspace) }
    it { should belong_to(:connector) }
  end

  describe "validations" do
    it { should validate_presence_of(:workspace_id) }
    it { should validate_presence_of(:connector_id) }
    it { should validate_presence_of(:catalog) }
    it { should validate_presence_of(:catalog_hash) }
  end

  describe "#find_stream_by_name" do
    let(:streams) do
      [
        { "name" => "profile", "other_attributes" => "value1" },
        { "name" => "customer", "other_attributes" => "value2" }
      ]
    end
    let(:catalog) { create(:catalog, catalog: { "streams" => streams }) }

    it "returns the correct stream when it exists" do
      stream = catalog.find_stream_by_name("profile")
      expect(stream).to eq({ "name" => "profile", "other_attributes" => "value1" })
    end

    it "returns nil when the stream does not exist" do
      stream = catalog.find_stream_by_name("non_existent")
      expect(stream).to be_nil
    end
  end

  describe "#to_protocol" do
    let(:catalog) do
      Catalog.create(
        catalog: {
          "streams" => [
            {
              "name" => "test_stream",
              "url" => "http://example.com",
              "json_schema" => {},
              "request_method" => "GET",
              "batch_support" => false,
              "batch_size" => 0,
              "request_rate_limit" => 10,
              "request_rate_limit_unit" => "minute",
              "request_rate_concurrency" => 1
            }
          ],
          "request_rate_limit" => 5,
          "request_rate_limit_unit" => "minute",
          "request_rate_concurrency" => 2
        },
        catalog_hash: "examplehash"
      )
    end

    context "with stream specific rate limits" do
      it "returns a protocol object with stream specific rate limits" do
        stream = catalog.find_stream_by_name("test_stream")
        protocol = catalog.stream_to_protocol(stream)

        expect(protocol.name).to eq("test_stream")
        expect(protocol.url).to eq("http://example.com")
        expect(protocol.json_schema).to eq({})
        expect(protocol.request_method).to eq("GET")
        expect(protocol.batch_support).to be_falsey
        expect(protocol.batch_size).to eq(0)
        expect(protocol.request_rate_limit).to eq(10)
        expect(protocol.request_rate_limit_unit).to eq("minute")
        expect(protocol.request_rate_concurrency).to eq(1)
      end

      context "with global rate limits" do
        it "returns a protocol object with global rate limits" do
          stream = catalog.catalog["streams"].first.except("request_rate_limit", "request_rate_limit_unit",
                                                           "request_rate_concurrency")
          protocol = catalog.stream_to_protocol(stream)

          expect(protocol.request_rate_limit).to eq(5)
          expect(protocol.request_rate_limit_unit).to eq("minute")
          expect(protocol.request_rate_concurrency).to eq(2)
        end
      end
    end

    describe "#default_cursor_field" do
      context "when source_defined_cursor is true and the default_cursor_field exists" do
        let(:catalog) do
          {
            "streams" => [
              { "name" => "stream1" },
              { "name" => "stream2" }
            ],
            "source_defined_cursor" => true,
            "default_cursor_field" => "timestamp"
          }
        end

        let(:workspace) { create(:workspace) }
        let(:connector) { create(:connector) }
        let(:catalog_instance) { create(:catalog, workspace:, connector:, catalog:) }

        it "returns the default cursor field" do
          expect(catalog_instance.default_cursor_field).to eq("timestamp")
        end
      end

      context "when source_defined_cursor is not defined" do
        let(:catalog_user_defined) do
          {
            "streams" => [
              { "name" => "stream1" },
              { "name" => "stream2" }
            ]
          }
        end

        let(:workspace) { create(:workspace) }
        let(:connector) { create(:connector) }
        let(:catalog_instance_user_defined) do
          create(:catalog, workspace:, connector:, catalog: catalog_user_defined)
        end

        it "returns nil" do
          expect(catalog_instance_user_defined.default_cursor_field).to be_nil
        end
      end

      context "when the source_defined_cursor is false" do
        let(:catalog_stream_not_exist) do
          {
            "streams" => [
              { "name" => "stream3" },
              { "name" => "stream4" }
            ],
            "source_defined_cursor" => false,
            "default_cursor_field" => "timestamp"
          }
        end

        let(:workspace) { create(:workspace) }
        let(:connector) { create(:connector) }
        let(:catalog_instance_stream_not_exist) do
          create(:catalog, workspace:, connector:, catalog: catalog_stream_not_exist)
        end

        it "returns nil" do
          expect(catalog_instance_stream_not_exist.default_cursor_field).to be_nil
        end
      end
    end
  end
end
