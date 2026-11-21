require "./spec_helper"
require "../../src/commands/docs"

module Shards::Commands
  describe Docs do
    describe ".convert_headings_to_markdown" do
      it "converts each heading level from h1 to h6" do
        (1..6).each do |level|
          html = %(<h#{level} id="section-#{level}" class="title">Level #{level}</h#{level}>)

          Docs.convert_headings_to_markdown(html).should eq("#{"#" * level} Level #{level}\n\n")
        end
      end

      it "strips tags nested inside the heading" do
        html = %(<h3><a href="#install">Install</a> with <code>minecart</code></h3>)

        Docs.convert_headings_to_markdown(html).should eq("### Install with minecart\n\n")
      end

      it "converts several headings in one pass, each up to its own closing tag" do
        html = "<h1>Title</h1><p>Intro</p><h2>Usage</h2><h1>Again</h1>"

        Docs.convert_headings_to_markdown(html).should eq("# Title\n\n<p>Intro</p>## Usage\n\n# Again\n\n")
      end

      it "keeps line breaks inside a heading" do
        Docs.convert_headings_to_markdown("<h2>First\nSecond</h2>").should eq("## First\nSecond\n\n")
      end

      it "converts an empty heading" do
        Docs.convert_headings_to_markdown("<h4></h4>").should eq("#### \n\n")
      end

      it "closes a heading only at the tag of its own level" do
        Docs.convert_headings_to_markdown("<h2>a</h3> b</h2>").should eq("## a b\n\n")
        Docs.convert_headings_to_markdown("<h2>unclosed</h3>").should eq("<h2>unclosed</h3>")
      end

      it "takes the outer heading when headings are nested" do
        Docs.convert_headings_to_markdown("<h2>x<h1>y</h1></h2>").should eq("## xy\n\n")
      end

      it "leaves tags that are not h1 to h6 unchanged" do
        html = "<h7>x</h7><header>y</header><hr>"

        Docs.convert_headings_to_markdown(html).should eq(html)
      end
    end
  end
end
