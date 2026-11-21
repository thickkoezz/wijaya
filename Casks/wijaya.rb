# Homebrew Cask untuk Wijaya — jalur distribusi gratis (tanpa Developer ID).
#
# Pasang dari tap:
#   brew tap thickkoezz/wijaya
#   brew install --cask wijaya
#
# Instal via Homebrew menghindari peringatan Gatekeeper (unduhan tidak diberi
# atribut quarantine), sehingga tidak butuh tanda tangan Apple yang berbayar.

cask "wijaya" do
  version "1.0"
  sha256 "2a78b767d5fa4ffee28de14dec76f328362232e8aa3d735fe86f7bea29e64637"

  url "https://github.com/thickkoezz/wijaya/releases/download/v#{version}/Wijaya-#{version}.dmg",
      verified: "github.com/thickkoezz/wijaya/"
  name "Wijaya"
  desc "GUI read-write NTFS for macOS (ntfs-3g + FUSE-T)"
  homepage "https://github.com/thickkoezz/wijaya"

  depends_on macos: ">= :sonoma"
  depends_on arch: :arm64
  # FUSE-T wajib ada:
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
