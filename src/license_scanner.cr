module Shards
  class LicenseScanner
    LICENSE_FILE_PATTERNS = [
      "LICENSE", "LICENSE.md", "LICENSE.txt",
      "LICENCE", "LICENCE.md", "LICENCE.txt",
      "LICENSE-MIT", "LICENSE-APACHE",
      "COPYING", "COPYING.md", "COPYING.txt",
    ]

    LICENSE_PATTERNS = [
      {/MIT License|Permission is hereby granted, free of charge/i, "MIT"},
      {/Apache License.*Version 2\.0/i, "Apache-2.0"},
      {/BSD 2-Clause|Redistribution and use.*two conditions/i, "BSD-2-Clause"},
      {/BSD 3-Clause|Redistribution and use.*three conditions/i, "BSD-3-Clause"},
      {/ISC License/i, "ISC"},
      {/Mozilla Public License.*2\.0/i, "MPL-2.0"},
      {/GNU General Public License.*version 3/i, "GPL-3.0-only"},
      {/GNU General Public License.*version 2/i, "GPL-2.0-only"},
      {/GNU Lesser General Public License.*version 3/i, "LGPL-3.0-only"},
      {/GNU Lesser General Public License.*version 2\.1/i, "LGPL-2.1-only"},
      {/GNU Affero General Public License.*version 3/i, "AGPL-3.0-only"},
      {/The Unlicense|unlicense\.org/i, "Unlicense"},
      {/Creative Commons Zero|CC0 1\.0/i, "CC0-1.0"},
      {/zlib License/i, "Zlib"},
    ]

    record ScanResult,
      license_file_path : String?,
      detected_license : String?,
      detection_confidence : Symbol

    def self.scan(install_path : String) : ScanResult
      license_file = find_license_file(install_path)
      if license_file
        content = File.read(license_file)
        detected, confidence = detect_license(content)
        ScanResult.new(
          license_file_path: Path[license_file].relative_to(install_path).to_s,
          detected_license: detected,
          detection_confidence: confidence
        )
      else
        ScanResult.new(license_file_path: nil, detected_license: nil, detection_confidence: :none)
      end
    end

    def self.find_license_file(dir : String) : String?
      LICENSE_FILE_PATTERNS.each do |pattern|
        path = File.join(dir, pattern)
        return path if File.exists?(path)
      end
      nil
    end

    def self.detect_license(content : String) : {String?, Symbol}
      LICENSE_PATTERNS.each do |regex, spdx_id|
        if content.matches?(regex)
          return {spdx_id, :high}
        end
      end
      {nil, :none}
    end
  end
end
