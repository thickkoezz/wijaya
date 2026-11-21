# Homebrew Cask untuk Wijaya — jalur distribusi GRATIS (tanpa Developer ID).
#
# Ini TEMPLATE. Ganti USER dan sha256 (lihat `bash scripts/release.sh`).
# Taruh file ini di repo tap-mu dengan struktur: Casks/wijaya.rb
#
# Pengguna lalu cukup:
#   brew tap USER/wijaya
#   brew install --cask wijaya
#
# Instal via Homebrew menghindari peringatan Gatekeeper (unduhan tidak diberi
# atribut quarantine), sehingga tidak butuh tanda tangan Apple yang berbayar.

cask "wijaya" do
  version "1.0"
  sha256 "REPLACE_WITH_SHA256_OF_DMG"

  url "https://github.com/USER/wijaya/releases/download/v#{version}/Wijaya-#{version}.dmg",
      verified: "github.com/USER/wijaya/"
  name "Wijaya"
  desc "GUI read-write NTFS for macOS (ntfs-3g + FUSE-T)"
  homepage "https://github.com/USER/wijaya"

  depends_on macos: ">= :sonoma"
  depends_on arch: :arm64
  # FUSE-T wajib ada; pasang salah satu (lihat catatan di bawah):
  #   brew install --cask macos-fuse-t/homebrew-cask/fuse-t

  # .dmg berisi installer .pkg yang memasang app + driver ntfs-3g.
  pkg "Wijaya-#{version}.pkg"

  uninstall pkgutil: "dev.mieky.wijaya",
            script:  {
              executable: "/bin/rm",
              args:       ["-f", "/usr/local/bin/ntfs-3g", "/usr/local/lib/libntfs-3g.dylib"],
              sudo:       true,
            }

  caveats <<~EOS
    Setelah instalasi, beri Full Disk Access (sekali saja):
      System Settings -> Privacy & Security -> Full Disk Access, tambahkan:
        /usr/local/bin/ntfs-3g
        /bin/bash
        Wijaya.app
    Prasyarat: FUSE-T terpasang —
      brew install --cask macos-fuse-t/homebrew-cask/fuse-t
  EOS
end
