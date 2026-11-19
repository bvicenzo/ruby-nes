# frozen_string_literal: true

require 'ruby/nes/frontends/input_script'

# The headless frontend's input script (plan 16, decision 3): YAML mapping frame numbers, from 1, to the buttons of
# the first controller held from that frame until the next entry, by their names in Input::Controller::BUTTONS.
RSpec.describe Ruby::Nes::Frontends::InputScript do
  describe '.parse' do
    context 'when the text is not valid YAML' do
      let(:text) { "120: [start\n" }

      it 'raises an invalid script error' do
        expect { described_class.parse(text) }.to raise_error(described_class::InvalidScript)
      end
    end

    context 'when the text is YAML' do
      context 'but it holds a value safe loading refuses' do
        let(:text) { "2024-01-01: [start]\n" }

        it 'raises an invalid script error' do
          expect { described_class.parse(text) }.to raise_error(described_class::InvalidScript, /Date/)
        end
      end

      context 'but it is empty' do
        let(:text) { '' }

        it 'returns a script that holds nothing' do
          expect(described_class.parse(text).buttons_at(1)).to eq(0)
        end
      end

      context 'but it is not a mapping' do
        let(:text) { "- start\n" }

        it 'raises an invalid script error' do
          expect { described_class.parse(text) }.to raise_error(described_class::InvalidScript, /frame numbers/)
        end
      end

      context 'and it is a mapping' do
        context 'but a frame is not an integer' do
          let(:text) { "start: [a]\n" }

          it 'raises an invalid script error' do
            expect { described_class.parse(text) }.to raise_error(described_class::InvalidScript, /"start"/)
          end
        end

        context 'but a frame is below 1' do
          let(:text) { "0: [a]\n" }

          it 'raises an invalid script error' do
            expect { described_class.parse(text) }.to raise_error(described_class::InvalidScript, /^0 is not/)
          end
        end

        context 'and every frame is an integer from 1' do
          context 'but the buttons of a frame are not a list' do
            let(:text) { "1: start\n" }

            it 'raises an invalid script error' do
              expect { described_class.parse(text) }.to raise_error(described_class::InvalidScript, /frame 1/)
            end
          end

          context 'and the buttons of every frame are a list' do
            context 'but a button is unknown' do
              let(:text) { "1: [start, turbo]\n" }

              it 'raises an invalid script error' do
                expect { described_class.parse(text) }.to raise_error(described_class::InvalidScript, /"turbo"/)
              end
            end

            context 'and every button is known' do
              let(:text) { "1: [a, right]\n30: []\n" }

              it "holds each entry's buttons from its frame on", :aggregate_failures do
                script = described_class.parse(text)
                expect(script.buttons_at(1)).to eq(0x81)
                expect(script.buttons_at(30)).to eq(0x00)
              end
            end
          end
        end
      end
    end
  end

  describe '#buttons_at' do
    context 'when the script has no entries' do
      subject(:script) { described_class.new({}) }

      it 'holds nothing' do
        expect(script.buttons_at(1)).to eq(0)
      end
    end

    context 'when the frame is before the first entry' do
      subject(:script) { described_class.new({ 120 => 0x08, 125 => 0x00 }) }

      it 'holds nothing' do
        expect(script.buttons_at(119)).to eq(0)
      end
    end

    context "when the frame is an entry's frame" do
      subject(:script) { described_class.new({ 120 => 0x08, 125 => 0x00 }) }

      it "holds the entry's buttons" do
        expect(script.buttons_at(120)).to eq(0x08)
      end
    end

    context 'when the frame is between two entries' do
      subject(:script) { described_class.new({ 120 => 0x08, 125 => 0x00 }) }

      it "holds the earlier entry's buttons" do
        expect(script.buttons_at(124)).to eq(0x08)
      end
    end

    context 'when the frame is past the last entry' do
      subject(:script) { described_class.new({ 120 => 0x08, 125 => 0x81 }) }

      it "holds the last entry's buttons" do
        expect(script.buttons_at(500)).to eq(0x81)
      end
    end
  end
end
