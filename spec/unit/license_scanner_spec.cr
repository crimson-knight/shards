require "./spec_helper"
require "../../src/license_scanner"

module Shards
  describe LicenseScanner do
    describe ".scan" do
      it "detects MIT from standard MIT LICENSE file content" do
        dir = File.tempname("license_scanner", "test")
        begin
          Dir.mkdir_p(dir)
          File.write(File.join(dir, "LICENSE"), <<-TEXT
          MIT License

          Copyright (c) 2024 Test Author

          Permission is hereby granted, free of charge, to any person obtaining a copy
          of this software and associated documentation files (the "Software"), to deal
          in the Software without restriction, including without limitation the rights
          to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
          copies of the Software, and to permit persons to whom the Software is
          furnished to do so, subject to the following conditions:
          TEXT
          )

          result = LicenseScanner.scan(dir)
          result.license_file_path.should eq("LICENSE")
          result.detected_license.should eq("MIT")
          result.detection_confidence.should eq(:high)
        ensure
          Shards::Helpers.rm_rf(dir)
        end
      end

      it "detects Apache-2.0 from Apache license content" do
        dir = File.tempname("license_scanner", "test")
        begin
          Dir.mkdir_p(dir)
          File.write(File.join(dir, "LICENSE"), "Apache License, Version 2.0, January 2004\nhttp://www.apache.org/licenses/\n\nTERMS AND CONDITIONS FOR USE, REPRODUCTION, AND DISTRIBUTION")

          result = LicenseScanner.scan(dir)
          result.detected_license.should eq("Apache-2.0")
          result.detection_confidence.should eq(:high)
        ensure
          Shards::Helpers.rm_rf(dir)
        end
      end

      it "detects GPL-3.0-only from GPL v3 content" do
        dir = File.tempname("license_scanner", "test")
        begin
          Dir.mkdir_p(dir)
          File.write(File.join(dir, "LICENSE"), "GNU General Public License, version 3, 29 June 2007\n\nCopyright (C) 2007 Free Software Foundation, Inc.")

          result = LicenseScanner.scan(dir)
          result.detected_license.should eq("GPL-3.0-only")
          result.detection_confidence.should eq(:high)
        ensure
          Shards::Helpers.rm_rf(dir)
        end
      end

      it "returns nil when no license file exists" do
        dir = File.tempname("license_scanner", "test")
        begin
          Dir.mkdir_p(dir)

          result = LicenseScanner.scan(dir)
          result.license_file_path.should be_nil
          result.detected_license.should be_nil
          result.detection_confidence.should eq(:none)
        ensure
          Shards::Helpers.rm_rf(dir)
        end
      end

      it "handles LICENCE (British spelling)" do
        dir = File.tempname("license_scanner", "test")
        begin
          Dir.mkdir_p(dir)
          File.write(File.join(dir, "LICENCE"), "MIT License\n\nCopyright (c) 2024")

          result = LicenseScanner.scan(dir)
          result.license_file_path.should eq("LICENCE")
          result.detected_license.should eq("MIT")
        ensure
          Shards::Helpers.rm_rf(dir)
        end
      end

      it "handles LICENSE.md" do
        dir = File.tempname("license_scanner", "test")
        begin
          Dir.mkdir_p(dir)
          File.write(File.join(dir, "LICENSE.md"), "# MIT License\n\nPermission is hereby granted, free of charge")

          result = LicenseScanner.scan(dir)
          result.license_file_path.should eq("LICENSE.md")
          result.detected_license.should eq("MIT")
        ensure
          Shards::Helpers.rm_rf(dir)
        end
      end

      it "handles LICENSE.txt" do
        dir = File.tempname("license_scanner", "test")
        begin
          Dir.mkdir_p(dir)
          File.write(File.join(dir, "LICENSE.txt"), "MIT License\n\nCopyright (c) 2024")

          result = LicenseScanner.scan(dir)
          result.license_file_path.should eq("LICENSE.txt")
          result.detected_license.should eq("MIT")
        ensure
          Shards::Helpers.rm_rf(dir)
        end
      end

      it "handles COPYING file" do
        dir = File.tempname("license_scanner", "test")
        begin
          Dir.mkdir_p(dir)
          File.write(File.join(dir, "COPYING"), "GNU General Public License, version 2, June 1991")

          result = LicenseScanner.scan(dir)
          result.license_file_path.should eq("COPYING")
          result.detected_license.should eq("GPL-2.0-only")
        ensure
          Shards::Helpers.rm_rf(dir)
        end
      end

      it "returns correct confidence :high for strong matches" do
        dir = File.tempname("license_scanner", "test")
        begin
          Dir.mkdir_p(dir)
          File.write(File.join(dir, "LICENSE"), "MIT License")

          result = LicenseScanner.scan(dir)
          result.detection_confidence.should eq(:high)
        ensure
          Shards::Helpers.rm_rf(dir)
        end
      end

      it "returns :none when no pattern matches" do
        dir = File.tempname("license_scanner", "test")
        begin
          Dir.mkdir_p(dir)
          File.write(File.join(dir, "LICENSE"), "This is some custom license text that does not match any known pattern.")

          result = LicenseScanner.scan(dir)
          result.license_file_path.should eq("LICENSE")
          result.detected_license.should be_nil
          result.detection_confidence.should eq(:none)
        ensure
          Shards::Helpers.rm_rf(dir)
        end
      end
    end

    describe ".find_license_file" do
      it "returns first matching pattern in priority order" do
        dir = File.tempname("license_scanner", "test")
        begin
          Dir.mkdir_p(dir)
          # Create both LICENSE and COPYING; LICENSE should be found first
          File.write(File.join(dir, "LICENSE"), "MIT License")
          File.write(File.join(dir, "COPYING"), "MIT License")

          result = LicenseScanner.find_license_file(dir)
          result.should_not be_nil
          result.not_nil!.should eq(File.join(dir, "LICENSE"))
        ensure
          Shards::Helpers.rm_rf(dir)
        end
      end
    end

    describe ".detect_license" do
      it "returns nil for non-license text" do
        detected, confidence = LicenseScanner.detect_license("Hello World, this is just a regular README file with no license information.")
        detected.should be_nil
        confidence.should eq(:none)
      end
    end
  end
end
