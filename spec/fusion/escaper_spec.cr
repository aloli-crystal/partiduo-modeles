# SPDX-License-Identifier: AGPL-3.0-or-later

require "../spec_helper"

private alias Escaper = Modeles::Fusion::Escaper

describe Modeles::Fusion::Escaper do
  it "neutralise les caractères actifs d'AsciiDoc" do
    escaped = Escaper.escape("asciidoc", "Durand *& Fils* | _x_ {attr} [lien] <b> +1 -- a\\b")
    escaped.should_not contain("*")
    escaped.should_not contain("|")
    escaped.should_not contain("{")
    escaped.should_not contain("--")
    escaped.should contain("&#42;&#38; Fils&#42;")
    escaped.should contain("&#124;")
  end

  it "neutralise un début de ligne actif en AsciiDoc et force les retours à la ligne" do
    Escaper.escape("asciidoc", "= Titre\n. liste\n  12 rue").should eq("&#61; Titre +\n&#46; liste +\n12 rue")
  end

  it "neutralise les caractères actifs de Markdown" do
    Escaper.escape("markdown", "Durand *& Fils* | _x_ [lien](url) <b> #1").should eq(
      "Durand \\*\\& Fils\\* \\| \\_x\\_ \\[lien\\](url) \\<b\\> \\#1")
    Escaper.escape("markdown", "- tiret\n1. un").should eq("\\- tiret\\\n1\\. un")
  end

  it "remplace les retours à la ligne d'une cellule Markdown par un espace" do
    Escaper.escape("markdown", "Conseil\nsur site", inline: true).should eq("Conseil sur site")
  end

  it "marque retours à la ligne et tabulations en XML et retire les caractères interdits" do
    Escaper.escape("docx", "a\nb\tc\u{0001}d").should eq("a#{Escaper::NEWLINE}b#{Escaper::TAB}cd")
  end
end
