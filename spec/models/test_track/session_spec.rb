require 'rails_helper'

RSpec.describe TestTrack::Session do
  let(:controller) { instance_double(ApplicationController, cookies: cookies, request: request) }
  let(:cookies) { { tt_visitor_id: "fake_visitor_id", mp_fakefakefake_mixpanel: mixpanel_cookie }.with_indifferent_access }
  let(:mixpanel_cookie) { URI.escape({ distinct_id: "fake_distinct_id", OtherProperty: "bar" }.to_json) }
  let(:request) { double(:request, host: "www.foo.com", ssl?: true) }
  let(:notification_job) { instance_double(TestTrack::NotificationJob, perform: true) }

  subject { described_class.new(controller) }

  before do
    allow(Delayed::Job).to receive(:enqueue).and_return(true)
    allow(TestTrack::NotificationJob).to receive(:new).and_return(notification_job)
    ENV['MIXPANEL_TOKEN'] = 'fakefakefake'
  end

  describe "#manage" do
    it "doesn't set a mixpanel cookie if already there" do
      subject.manage {}
      expect(cookies['mp_fakefakefake_mixpanel']).to eq mixpanel_cookie
    end

    it "sets a visitor ID cookie" do
      subject.manage {}
      expect(cookies['tt_visitor_id'][:value]).to eq "fake_visitor_id"
    end

    context "with no visitor cookie" do
      let(:cookies) { { mp_fakefakefake_mixpanel: mixpanel_cookie }.with_indifferent_access }

      it "returns a new visitor id" do
        subject.manage {}
        expect(cookies['tt_visitor_id'][:value]).to match(/\A[a-z0-9\-]{36}\z/)
      end
    end

    it "sets correct visitor id if controller does a #log_in!" do
      real_visitor = instance_double(TestTrack::Visitor, id: "real_visitor_id", assignment_registry: {})
      identifier = instance_double(TestTrack::Identifier, visitor: real_visitor)
      allow(TestTrack::Identifier).to receive(:create!).and_return(identifier)

      subject.manage do
        subject.visitor_dsl.log_in!("indetifier_type", "value")
      end
      expect(cookies['tt_visitor_id'][:value]).to eq "real_visitor_id"
    end

    context "without mixpanel cookie" do
      let(:cookies) { { tt_visitor_id: "fake_visitor_id" }.with_indifferent_access }

      it "sets the mixpanel cookie's distinct_id to the visitor_id" do
        subject.manage {}
        expect(cookies['mp_fakefakefake_mixpanel'][:value]).to eq URI.escape({ distinct_id: 'fake_visitor_id' }.to_json)
      end
    end

    context "with malformed mixpanel cookie" do
      let(:cookies) { { tt_visitor_id: "fake_visitor_id", mp_fakefakefake_mixpanel: malformed_mixpanel_cookie }.with_indifferent_access }
      let(:malformed_mixpanel_cookie) do
        URI.escape("{\"distinct_id\": \"fake_distinct_id\", \"referrer\":\"http://bad.com/?q=\"bad\"\"}")
      end

      it "sets the mixpanel cookie's distinct_id to the visitor_id" do
        subject.manage {}
        expect(cookies['mp_fakefakefake_mixpanel'][:value]).to eq URI.escape({ distinct_id: 'fake_visitor_id' }.to_json)
      end

      it "logs an error" do
        allow(Rails.logger).to receive(:error).and_call_original
        subject.manage {}
        expect(Rails.logger).to have_received(:error).with(
          "malformed mixpanel JSON from cookie {\"distinct_id\": \"fake_distinct_id\", \"referrer\":\"http://bad.com/?q=\"bad\"\"}"
        )
      end
    end

    context "cookies" do
      it "sets secure cookies if the request is ssl" do
        allow(request).to receive(:ssl?).and_return(true)
        subject.manage {}
        expect(cookies['tt_visitor_id'][:secure]).to eq true
      end

      it "sets insecure cookies if the request isn't ssl" do
        allow(request).to receive(:ssl?).and_return(false)
        subject.manage {}
        expect(cookies['tt_visitor_id'][:secure]).to eq false
      end

      it "uses a wildcard domain" do
        allow(request).to receive(:host).and_return("foo.bar.baz.boom.com")
        subject.manage {}
        expect(cookies['tt_visitor_id'][:domain]).to eq ".boom.com"
      end

      it "doesn't set httponly cookies" do
        subject.manage {}
        expect(cookies['tt_visitor_id'][:httponly]).to eq false
      end

      it "expires in a year" do
        Timecop.freeze(Time.zone.parse('2011-01-01')) do
          subject.manage {}
        end
        expect(cookies['tt_visitor_id'][:expires]).to eq Time.zone.parse('2012-01-01')
      end
    end

    it "flushes notifications if there have been new assignments" do
      allow(TestTrack::SplitRegistry).to receive(:to_hash).and_return('bar' => { 'foo' => 0, 'baz' => 100 })
      subject.manage do
        subject.visitor_dsl.ab('bar', 'baz')
      end
      expect(TestTrack::NotificationJob).to have_received(:new).with(
        mixpanel_distinct_id: 'fake_distinct_id',
        visitor_id: 'fake_visitor_id',
        new_assignments: { 'bar' => 'baz' })
      expect(Delayed::Job).to have_received(:enqueue).with(notification_job)
    end

    it "doesn't flush notifications if there haven't been new assignments" do
      subject.manage {}
      expect(TestTrack::NotificationJob).not_to have_received(:new)
    end
  end

  describe "#visitor_dsl" do
    let(:visitor) { instance_double(TestTrack::Visitor) }

    it "is a DSL that proxies to the visitor" do
      allow(TestTrack::VisitorDSL).to receive(:new).and_call_original
      allow(TestTrack::Visitor).to receive(:new).and_return(visitor)

      subject.visitor_dsl

      expect(TestTrack::VisitorDSL).to have_received(:new).with(visitor)
    end
  end

  describe "#state_hash" do
    let(:visitor) { instance_double(TestTrack::Visitor, split_registry: "split registry", assignment_registry: "assignment registry") }
    before do
      allow(subject).to receive(:visitor).and_return(visitor)
    end

    it "includes the test track URL" do
      expect(subject.state_hash[:url]).to eq "http://testtrack.dev"
    end

    it "includes the cookie_domain" do
      allow(request).to receive(:host).and_return("foo.bar.baz.boom.com")
      expect(subject.state_hash[:cookieDomain]).to eq(".boom.com")
    end

    it "includes the split registry" do
      expect(subject.state_hash[:registry]).to eq("split registry")
    end

    it "includes the assignment registry" do
      expect(subject.state_hash[:assignments]).to eq("assignment registry")
    end

    it "includes a nil :registry if visitor returns a nil split_registry" do
      allow(visitor).to receive(:split_registry).and_return(nil)
      expect(subject.state_hash).to have_key(:registry)
      expect(subject.state_hash[:registry]).to eq(nil)
    end

    it "includes a nil :assignments if visitor returns a nil assignment_registry" do
      allow(visitor).to receive(:assignment_registry).and_return(nil)
      expect(subject.state_hash).to have_key(:assignments)
      expect(subject.state_hash[:assignments]).to eq(nil)
    end
  end
end
