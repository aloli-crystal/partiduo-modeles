# SPDX-License-Identifier: AGPL-3.0-or-later

require "../spec_helper"

private alias Files = Modeles::SpecSupport::OfficeFiles

describe Modeles::Office::Package do
  it "réécrit mimetype en premier et sans compression (ODF)" do
    bytes = Files.odt(Files.tp("Bonjour"))
    # En-tête local : signature, puis méthode de compression 0 (STORED) à
    # l'octet 8, nom « mimetype » à l'octet 30, contenu à l'octet 38.
    bytes[0, 4].should eq(Bytes[0x50, 0x4B, 0x03, 0x04])
    IO::ByteFormat::LittleEndian.decode(UInt16, bytes[8, 2]).should eq(0)
    String.new(bytes[30, 8]).should eq("mimetype")
    String.new(bytes[38, Modeles::Office::Odt::MIMETYPE.size]).should eq(Modeles::Office::Odt::MIMETYPE)
  end

  it "relit une archive et garde l'ordre de ses entrées" do
    package = Modeles::Office::Package.read(Files.docx(Files.para(Files.r("x"))))
    package.names.should eq(["[Content_Types].xml", "_rels/.rels", "word/document.xml"])
    package.text("word/document.xml").to_s.should contain("<w:t>x</w:t>")
  end

  it "écrit deux fois la même archive pour le même contenu" do
    Files.docx(Files.para(Files.r("x"))).should eq(Files.docx(Files.para(Files.r("x"))))
  end

  it "refuse ce qui n'est pas une archive lisible" do
    expect_raises(Modeles::Office::InvalidPackage) { Modeles::Office::Package.read("pas un zip".to_slice) }
    expect_raises(Modeles::Office::InvalidPackage) { Modeles::Office::Package.read(Bytes.empty) }
  end
end
