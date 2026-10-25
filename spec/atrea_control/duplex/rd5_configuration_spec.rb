# frozen_string_literal: true

RSpec.describe AtreaControl::Duplex::RD5Configuration do
  subject(:configuration) { described_class.new(registers) }

  let(:registers) { { "H11300" => 0, "H10501" => 1, "H10200" => 1, "I10200" => 65_486 } }

  it "copies and freezes unsigned configuration without requiring command registers" do
    registers["H10510"] = 65_535
    expect(configuration.to_h).to eq("H11300" => 0, "H10501" => 1, "H10510" => 65_535)
    registers["H10510"] = 0
    expect(configuration.fetch("H10510")).to eq(65_535)
  end

  it "freezes itself and its configuration projection" do
    expect(configuration.to_h).to be_frozen
    expect(configuration).to be_frozen
  end

  %w[H10510 H10501 H11300 H11700 C10508 C10509 I11401 H10700 H10701].each do |id|
    it "exposes #{id} for future command policy" do
      registers[id] = 2
      expect(configuration.fetch(id)).to eq(2)
    end
  end

  it "reports missing command configuration only on fetch" do
    expect(configuration["H11700"]).to be_nil
    expect { configuration.fetch("H11700") }.to raise_error(AtreaControl::UnsupportedConfiguration, /H11700/)
  end

  describe "standard inlet resolver" do
    [
      [{}, 65_486],
      [{ "H10501" => 2, "H10201" => 1, "I10201" => 231 }, 231],
      [{ "H11300" => 1, "I10204" => 205 }, 205],
      [{ "H11300" => 1, "I10204" => 0 }, 0],
      [{ "H10501" => 2, "H10201" => 1, "I10201" => 65_486 }, 65_486],
      [{ "I10200" => 0 }, 0],
      [{ "H10200" => 0 }, nil],
      [{ "I10200" => 1260 }, nil],
      [{ "H10501" => 2, "H10201" => 0, "I10201" => 231 }, nil],
      [{ "H10501" => 2, "H10201" => 1, "I10201" => 1260 }, nil],
      [{ "H10501" => 3 }, nil],
      [{ "H11300" => 2 }, nil],
      [{ "H11300" => 1 }, nil]
    ].each do |overrides, expected|
      it "resolves #{overrides.inspect} to #{expected.inspect}" do
        registers.merge!(overrides)
        expect(configuration.input_temperature).to eq(expected)
      end
    end

    %w[H11300 H10501 H10200 I10200].each do |id|
      it "returns nil when optional #{id} is absent" do
        registers.delete(id)
        expect(configuration.input_temperature).to be_nil
      end
    end

    %w[H10201 I10201].each do |id|
      it "returns nil when M2 is selected but #{id} is absent" do
        registers.merge!("H10501" => 2, "H10201" => 1, "I10201" => 231).delete(id)
        expect(configuration.input_temperature).to be_nil
      end
    end
  end

  describe "power command policy" do
    {
      0 => [0, *(12..100)],
      1 => (0..100).to_a,
      2 => [0, 1, 2],
      4 => [0, *(10..12), *(20..22), *(30..38)],
    }.each do |profile, allowed|
      it "validates every power boundary for H10510=#{profile}" do # rubocop:disable RSpec/ExampleLength
        registers["H10510"] = profile
        (0..101).each do |value|
          if allowed.include?(value)
            expect(configuration.validate_power!(value)).to eq(value)
          else
            expect { configuration.validate_power!(value) }.to raise_error(ArgumentError)
          end
        end
      end
    end

    [nil, 3, 5, 65_535].each do |profile|
      it "rejects missing or unsupported power profile #{profile.inspect}" do
        registers["H10510"] = profile unless profile.nil?
        expect { configuration.validate_power!(0) }.to raise_error(AtreaControl::UnsupportedConfiguration)
      end
    end
  end

  describe "mode command policy" do
    let(:modes) { (0..7).to_h { |mode| [mode.to_s, "translated label"] } }

    { 0 => {}, 2 => {}, 1 => { "C10508" => 0 }, 6 => { "C10508" => 0 }, 7 => { "C10508" => 0 },
      3 => { "C10508" => 0, "C10509" => 1 }, 4 => { "C10508" => 0, "H11700" => 1 },
      5 => { "I11401" => 1 }, }.each do |mode, prerequisites|
      it "allows mode #{mode} with its exact prerequisites and translated label" do
        registers.merge!(prerequisites)
        expect(configuration.validate_mode!(mode, modes)).to eq(mode)
      end

      prerequisites.each do |id, expected|
        [nil, 1 - expected, 2].each do |invalid|
          it "rejects mode #{mode} when #{id}=#{invalid.inspect}" do
            registers.merge!(prerequisites)
            invalid.nil? ? registers.delete(id) : registers[id] = invalid
            expect { configuration.validate_mode!(mode, modes) }.to raise_error(AtreaControl::UnsupportedConfiguration)
          end
        end
      end
    end

    it "rejects undiscovered mode even when prerequisites match" do
      expect { configuration.validate_mode!(0, modes.except("0")) }.to raise_error(AtreaControl::UnsupportedConfiguration)
    end

    [-1, 8, 65_535].each do |mode|
      it "rejects mode outside 0..7: #{mode}" do
        expect { configuration.validate_mode!(mode, modes) }.to raise_error(ArgumentError)
      end
    end
  end
end
