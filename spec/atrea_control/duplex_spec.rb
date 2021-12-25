AtreaControl::Duplex::CONTROL_URI = "file://#{File.join(__dir__, "../fixtures/files/login.html")}"

RSpec.describe AtreaControl::Duplex do

  context "with logged" do
    before do
      duplex.instance_variable_set :@logged, true
      duplex.driver.get "file://#{File.join(__dir__, "../fixtures/files/dashboard.html")}"
      duplex.send(:refresh!)
    end

  end
end
