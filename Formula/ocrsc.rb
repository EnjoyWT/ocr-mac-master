class Ocrsc < Formula
  desc "OCR Cluster HTTP service using macOS Vision Framework"
  homepage "https://github.com/EnjoyWT/ocr-cluster"
  url "https://github.com/EnjoyWT/ocr-cluster/archive/refs/tags/v0.0.1.tar.gz"
  sha256 "SHA256_PLACEHOLDER"
  license "MIT"

  depends_on :macos => :monterey
  depends_on :xcode => ["13.0", :build]

  def install
    system "swift", "build", "-c", "release", "--disable-sandbox"
    bin.install ".build/release/ocrsc" => "ocrsc"
    (etc/"ocrsc").mkpath
    (etc/"ocrsc/config.json").write <<~EOS
      {
        "host": "0.0.0.0",
        "port": 7322,
        "log_level": "info",
        "max_file_size": "10MB"
      }
    EOS
  end

  service do
    run [opt_bin/"ocrsc", "--config", etc/"ocrsc/config.json"]
    keep_alive true
    log_path var/"log/ocrsc.log"
    error_log_path var/"log/ocrsc.error.log"
  end

  test do
    system "#{bin}/ocrsc", "--version"
  end
end 