# frozen_string_literal: true

require "nokogiri"

RSpec.describe AtreaControl::Duplex::RD5Command do
  let(:layout) { Nokogiri::XML(File.read(File.join(__dir__, "../../fixtures/files/userCtrl.xml"))) }

  { power: ["$currentPower", "H10708", "H10700"], mode: ["$currentMode", "H10709", "H10701"] }.each do |setting, (title, input, switch)|
    context "with #{setting} profile" do
      let(:node) { layout.at_xpath("//i[@title='#{title}']/onchange") }
      let(:source) { node.text }

      def discover(text, setting)
        described_class.discover(text, power: setting == :power)
      end

      it "accepts the fixture's usual whitespace" do
        expect(discover(source, setting)).to eq(input: input, switch: switch)
      end

      it "accepts spaces, tabs and newlines between JavaScript tokens" do
        formatted = source.gsub(/(==|&&|[(),;{}=+?:>])/, " \t\\1\n ")
        # Quoted '&' and empty literals remain unchanged by punctuation formatting.
        expect(discover(formatted, setting)).to eq(input: input, switch: switch)
      end

      [input, switch].each do |id|
        [" ", "\t", "\n", "\r\n", "/*comment*/", "//comment\n", "\\n"].each do |insertion|
          it "rejects #{insertion.inspect} inside quoted #{id}" do
            malformed = source.sub("'#{id}'", "'#{id[0, 4]}#{insertion}#{id[4..]}'")
            expect { discover(malformed, setting) }.to raise_error(AtreaControl::UnsupportedConfiguration)
          end
        end
      end

      ["getUrl Par", "getUrl/*comment*/Par", "getUrl//comment\nPar"].each do |replacement|
        it "rejects split or commented function name #{replacement.inspect}" do
          expect { discover(source.sub("getUrlPar", replacement), setting) }.to raise_error(AtreaControl::UnsupportedConfiguration)
        end
      end

      ["//comment\n", "/*comment*/"].each do |comment|
        it "rejects unsupported comment #{comment.inspect} between tokens" do
          expect { discover(source.sub("saved=true;", "saved=true;#{comment}"), setting) }.to raise_error(AtreaControl::UnsupportedConfiguration)
        end
      end

      [" ", "\n", "/*comment*/", "//comment\n"].each do |insertion|
        it "rejects quoted ID containing #{insertion.inspect} before any HTTP write" do # rubocop:disable RSpec/ExampleLength
          node.content = source.sub("'#{input}'", "'#{input[0, 4]}#{insertion}#{input[4..]}'")
          stub_request(:get, %r{/comm/sw/unit.php}).with(query: hash_including("_t" => "lang/userCtrl.xml")).to_return(body: layout.to_xml)
          texts = File.read(File.join(__dir__, "../../fixtures/files/texts.xml"))
          stub_request(:get, %r{/comm/sw/unit.php}).with(query: hash_including("_t" => "config/texts.xml")).to_return(body: texts)
          snapshot = Nokogiri::XML(File.read(File.join(__dir__, "../../fixtures/files/unit.xml")))
          snapshot.root["t"] = Time.now.strftime("%Y-%m-%d %H:%M:%S")
          stub_request(:get, %r{/comm/sw/unit.php}).with(query: hash_including("_t" => "config/xml.xml")).to_return(body: snapshot.to_xml)
          write = stub_request(:get, %r{/comm/sw/unit.php}).with(query: hash_including("_w" => "1"))
          unit = AtreaControl::Duplex::Unit.new(user_id: 1, unit_id: "unit", sid: "sid")
          expect { unit.public_send(:"#{setting}=", 0) }.to raise_error(AtreaControl::UnsupportedConfiguration)
          expect(write).not_to have_been_requested
        end
      end
    end
  end
end
