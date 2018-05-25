require 'rails_helper'

RSpec.describe TestTrack::Assignment do
  let(:visitor) { instance_double(TestTrack::Visitor, offline?: offline) }
  let(:offline) { false }

  subject { described_class.new(visitor: visitor, split_name: :split_name) }

  describe "#split_name" do
    it "returns a string" do
      expect(subject.split_name).to be_kind_of String
    end
  end

  describe "#variant" do
    let(:variant) { :the_variant }
    let(:variant_calculator) { instance_double(TestTrack::VariantCalculator, variant: variant) }

    before do
      allow(TestTrack::VariantCalculator).to receive(:new).and_return(variant_calculator)
    end

    it "returns a string" do
      expect(subject.variant).to be_kind_of String
    end

    context "when the visitor is online" do
      it "returns a variant generated by VariantCalculator" do
        expect(subject.variant).to eq "the_variant"
        expect(variant_calculator).to have_received(:variant)
      end
    end

    context "when the visitor is offline" do
      let(:offline) { true }

      it "returns nil" do
        expect(subject.variant).to eq nil
        expect(variant_calculator).not_to have_received(:variant)
      end
    end

    context "when the variant calculator returns nil" do
      let(:variant) { nil }

      it "returns nil" do
        expect(subject.variant).to eq nil
      end
    end
  end

  describe "#unsynced?" do
    it "returns true" do
      expect(subject.unsynced?).to eq true
    end

    context "for a feature gate" do
      subject { described_class.new(visitor: visitor, split_name: :feature_enabled) }

      it "also returns true" do
        expect(subject.unsynced?).to eq true
      end
    end
  end

  describe "#feature_gate?" do
    context "when the split name ends with '_enabled'" do
      subject { described_class.new(visitor: visitor, split_name: :feature_enabled) }

      it "returns true" do
        expect(subject.feature_gate?).to eq true
      end
    end

    context "when the split name ends with something else" do
      subject { described_class.new(visitor: visitor, split_name: :feature_experiment) }

      it "returns false" do
        expect(subject.feature_gate?).to eq false
      end
    end
  end
end
