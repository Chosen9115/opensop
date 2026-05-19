module Sop
  module Serializers
    # Summary serializer used by GET /sop/ (discovery).
    class ProcessSummarySerializer
      def initialize(process)
        @process = process
      end

      def as_json(*)
        definition = @process.definition || {}
        process_block = definition["process"] || {}

        {
          name: @process.name,
          version: @process.version,
          description: @process.description,
          tags: Array(@process.tags),
          inputs_summary: summary_for(process_block["inputs"]),
          outputs_summary: summary_for(process_block["outputs"]),
          sla: sla_for(process_block["sla"]),
          schema_url: "/sop/#{@process.name}/schema"
        }
      end

      # Turns `[{name: "x", type: "string", required: true}, ...]` into
      # `"x (string, required), y (email, required)"`.
      def self.summary_for(fields)
        Array(fields).map do |field|
          name = field["name"]
          type = field["type"] || field["format"] || "any"
          parts = [ type.to_s ]
          parts << "required" if field["required"]
          if field["type"] == "enum" && field["values"].is_a?(Array)
            parts = [ "enum: #{field["values"].join("|")}" ]
            parts << "required" if field["required"]
          end
          "#{name} (#{parts.join(", ")})"
        end.join(", ")
      end

      private

      def summary_for(fields)
        self.class.summary_for(fields)
      end

      def sla_for(sla)
        return nil if sla.blank?
        return sla if sla.is_a?(String)
        sla.is_a?(Hash) ? sla["target"] : nil
      end
    end
  end
end
