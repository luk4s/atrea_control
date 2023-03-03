# frozen_string_literal: true

RSpec.shared_context "userCtrl" do
  let(:user_modes) do
    {
      "0" => "Vypnuto",
      "1" => "Náběh",
      "2" => "Doběh",
      "3" => "koupelna",
      "4" => "wc",
      "5" => "CO2",
      "6" => "kuchyň",
      "7" => "ovladač",
    }
  end
  let(:user_texts) do
    {
      "D1" => "koupelna",
      "D2" => "wc",
      "D3" => "CO2",
      "D4" => "kuchyň",
      "IN1" => "ovladač",
      "IN2" => "text IN2",
      "UnitName" => "Byt 007",
    }
  end
  let(:modes) do
    {
      "0" => "Vypnuto",
      "1" => "Automat",
      "2" => "Větrání",
      "3" => "Větrání s cirkulací",
      "4" => "Cirkulace",
      "5" => "Noční předchlazení",
      "6" => "Rozvážení",
      "7" => "Přetlakové větrání",
    }
  end
  let(:sensors) do
    {
      "outdoor_temperature" => "I10208",
      "current_power" => "H10704",
      "current_mode" => "H10705",
      "current_mode_switch" => "H10712",
      "power_input" => "H10708",
      "mode_input" => "H10709",
      "mode_switch" => "H10701",
    }
  end
  let(:user_ctrl) do
    instance_double(AtreaControl::Duplex::UserCtrl, name: user_texts["UnitName"], user_modes: user_modes,
                                                    user_texts: user_texts, modes: modes, sensors: sensors)
  end
end
