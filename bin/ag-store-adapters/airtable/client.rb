# frozen_string_literal: true
# Minimal Airtable Web API client — stdlib only (net/http, json), no gem
# dependency, matching every other script in bin/. Handles auth, JSON
# encode/decode, pagination, and batching; knows nothing about Agentile's
# schema (see schema.rb) or op semantics (see ../airtable.rb).
require "net/http"
require "json"
require "uri"

module Airtable
  class ApiError < StandardError; end

  class Client
    API = "https://api.airtable.com"

    # `transport` is injectable for tests: a callable
    # ->(method, uri, headers, body_json) { [status_code, response_body_string] }
    # Default performs the real HTTPS request.
    def initialize(token:, transport: nil)
      raise ArgumentError, "airtable token is required" if token.to_s.empty?

      @token = token
      @transport = transport || method(:http_request)
    end

    def http_request(method, uri, headers, body_json)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      req = case method
            when :get then Net::HTTP::Get.new(uri)
            when :post then Net::HTTP::Post.new(uri)
            when :patch then Net::HTTP::Patch.new(uri)
            when :put then Net::HTTP::Put.new(uri)
            when :delete then Net::HTTP::Delete.new(uri)
            else raise ArgumentError, "unsupported method: #{method}"
            end
      headers.each { |k, v| req[k] = v }
      req.body = body_json if body_json
      res = http.request(req)
      [res.code.to_i, res.body]
    end

    # path is anything after the host, e.g. "/v0/meta/bases" or "/v0/appXXX/Specs".
    # query is a Hash of query params (repeated keys as arrays, Airtable's
    # bracket-array convention for e.g. fields[]=A&fields[]=B is handled by callers
    # pre-building the query string when needed).
    def request(method, path, body: nil, query: nil)
      uri = URI("#{API}#{path}")
      uri.query = URI.encode_www_form(query) if query && !query.empty?
      headers = { "Authorization" => "Bearer #{@token}", "Content-Type" => "application/json" }
      status, raw = @transport.call(method, uri, headers, body ? JSON.generate(body) : nil)
      parsed = raw.to_s.empty? ? {} : JSON.parse(raw)
      unless (200..299).cover?(status)
        message = parsed.is_a?(Hash) ? parsed.dig("error", "message") || parsed["error"] : raw
        raise ApiError, "airtable #{method.to_s.upcase} #{path} -> #{status}: #{message}"
      end
      parsed
    end

    # ---- records ----

    def list_records(base_id, table, filter_by_formula: nil)
      records = []
      offset = nil
      loop do
        query = {}
        query["filterByFormula"] = filter_by_formula if filter_by_formula
        query["offset"] = offset if offset
        page = request(:get, "/v0/#{base_id}/#{URI.encode_www_form_component(table)}", query: query)
        records.concat(page["records"] || [])
        offset = page["offset"]
        break unless offset
      end
      records
    end

    def get_record(base_id, table, record_id)
      request(:get, "/v0/#{base_id}/#{URI.encode_www_form_component(table)}/#{record_id}")
    end

    # Airtable accepts at most 10 records per create/update call — chunk transparently.
    def create_records(base_id, table, records_fields)
      records_fields.each_slice(10).flat_map do |chunk|
        body = { records: chunk.map { |f| { fields: f } } }
        request(:post, "/v0/#{base_id}/#{URI.encode_www_form_component(table)}", body: body)["records"]
      end
    end

    def update_record(base_id, table, record_id, fields)
      request(:patch, "/v0/#{base_id}/#{URI.encode_www_form_component(table)}/#{record_id}", body: { fields: fields })
    end

    def delete_record(base_id, table, record_id)
      request(:delete, "/v0/#{base_id}/#{URI.encode_www_form_component(table)}/#{record_id}")
    end

    # ---- metadata (schema) ----

    def list_tables(base_id)
      request(:get, "/v0/meta/bases/#{base_id}/tables")["tables"] || []
    end

    def create_table(base_id, name, fields)
      request(:post, "/v0/meta/bases/#{base_id}/tables", body: { name: name, fields: fields })
    end

    def create_field(base_id, table_id, field_def)
      request(:post, "/v0/meta/bases/#{base_id}/tables/#{table_id}/fields", body: field_def)
    end

    def create_base(workspace_id, name, tables)
      request(:post, "/v0/meta/bases", body: { workspaceId: workspace_id, name: name, tables: tables })
    end
  end
end
