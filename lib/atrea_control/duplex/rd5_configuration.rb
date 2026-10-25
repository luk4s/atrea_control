# frozen_string_literal: true

module AtreaControl
  module Duplex
    # Immutable policy over validated, unsigned registers from one RD5 snapshot.
    class RD5Configuration
      REGISTERS = %w[H10510 H10501 H11300 H11700 C10508 C10509 I11401 H10700 H10701].freeze
      POWER_DOMAINS = { 0 => [0, *(12..100)].freeze, 1 => (0..100), 2 => (0..2),
                        4 => [0, *(10..12), *(20..22), *(30..38)].freeze, }.freeze
      MODE_REQUIREMENTS = {
        0 => {}, 2 => {}, 1 => { "C10508" => 0 }, 6 => { "C10508" => 0 }, 7 => { "C10508" => 0 },
        3 => { "C10508" => 0, "C10509" => 1 }, 4 => { "C10508" => 0, "H11700" => 1 }, 5 => { "I11401" => 1 },
      }.transform_values(&:freeze).freeze

      # Recognize known logic as data, never execute configuration JavaScript.
      INLET_SOURCE_RULE = <<~JS.gsub(/\s+/, "").freeze
        function() {
          var val, na=false;
          if(values.H11300==0){
            if(values.H10501==1 && values.H10200>0 && values.I10200!=126.0)
              val=values.I10200;
            else if(values.H10501==2 && values.H10201>0 && values.I10201!=126.0)
              val=values.I10201;
            else
              na=true;
          }else if(values.H11300==1){
            val=values.I10204;
          }else na=true;
          if(na) return words['unavail'];
          return val;
        }
      JS

      def self.input_temperature_source(source)
        source.gsub(/\s+/, "") == INLET_SOURCE_RULE ? "rd5_standard" : "unsupported"
      end

      def initialize(registers)
        @registers = registers.dup.freeze
        @configuration = @registers.slice(*REGISTERS).freeze
        freeze
      end

      def [](id)
        @configuration[id]
      end

      # Command policy must explicitly request its prerequisites.
      def fetch(id)
        @configuration.fetch(id) { raise AtreaControl::UnsupportedConfiguration, "Missing configuration register #{id}" }
      end

      def to_h
        @configuration
      end

      def validate_power!(value)
        domain = POWER_DOMAINS.fetch(fetch("H10510")) { raise AtreaControl::UnsupportedConfiguration, "Unsupported power profile" }
        raise ArgumentError, "Power outside configured range" unless value.is_a?(Integer) && domain.include?(value)

        value
      end

      def validate_mode!(value, modes)
        raise ArgumentError, "Mode outside 0..7" unless value.is_a?(Integer) && (0..7).cover?(value)
        raise AtreaControl::UnsupportedConfiguration, "Undiscovered mode" unless modes.key?(value.to_s)

        MODE_REQUIREMENTS.fetch(value).each do |id, expected|
          raise AtreaControl::UnsupportedConfiguration, "Mode unavailable: #{id}" unless fetch(id) == expected
        end
        value
      end

      # Use the discovered switch from this same validated snapshot, including custom mappings.
      def temporary_control?(id)
        state = @registers.fetch(id) { raise AtreaControl::UnsupportedConfiguration, "Missing control register #{id}" }
        raise AtreaControl::UnsupportedConfiguration, "Unknown control state for #{id}" unless [0, 1, 2].include?(state)

        state != 0
      end

      # Supported userCtrl inlet source rule; return unsigned temperature or nil.
      def input_temperature
        case self["H11300"]
        when 0
          case self["H10501"]
          when 1 then fan_temperature("H10200", "I10200")
          when 2 then fan_temperature("H10201", "I10201")
          end
        when 1
          @registers["I10204"]
        end
      end

      private

      def fan_temperature(fan, sensor)
        speed = @registers[fan]
        temperature = @registers[sensor]
        temperature if speed&.positive? && temperature != 1260
      end
    end
  end
end
