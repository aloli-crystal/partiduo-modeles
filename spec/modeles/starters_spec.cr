# SPDX-License-Identifier: AGPL-3.0-or-later

require "../spec_helper"

describe "Modèles de départ (ADR-010 D6)" do
  it "fournit facture, devis et avoir dans les quatre formats et les trois langues" do
    list = Modeles::Starters.list
    list.size.should eq(3 * 4 * 3)
    list.map(&.filename).should contain("modele-facture-fr.odt")
    list.map(&.filename).should contain("modele-avoir-nl.docx")
    list.map(&.filename).should contain("modele-devis-en.md")
  end

  it "passe le contrôle du dépôt pour son type et se rend avec le document fictif" do
    Modeles::Starters.list.each do |starter|
      bytes = Modeles::Starters.file(starter.kind, starter.locale, starter.format)
      report = Modeles::Fusion.analyze(starter.format, bytes, starter.kind)
      {starter.filename, report.errors}.should eq({starter.filename, [] of Modeles::Fusion::Issue})
      view = Modeles::Sample.document(starter.kind, starter.locale, Time.utc(2026, 9, 15))
      rendered = Modeles::Fusion.render(starter.format, bytes, view)
      rendered.should_not be_empty
    end
  end

  it "rend des libellés dans la langue du modèle" do
    view = Modeles::Sample.document("invoice", "nl", Time.utc(2026, 9, 15))
    text = String.new(Modeles::Fusion.render("markdown", Modeles::Starters.file("invoice", "nl", "markdown"), view))
    text.should contain("| Omschrijving | Aantal |")
    text.should contain("Te betalen") if text.includes?("Afgetrokken")
    text.should contain("1.759,15 EUR")
    quote = Modeles::Sample.document("quote", "en", Time.utc(2026, 9, 15))
    String.new(Modeles::Fusion.render("asciidoc", Modeles::Starters.file("quote", "en", "asciidoc"), quote)).should contain("|Valid until |2026-10-15")
  end

  it "est à jour dans starters/ (script scripts/starters.cr)" do
    directory = File.join(Modeles::SpecSupport::ROOT, "starters")
    Modeles::Starters.list.each do |starter|
      path = File.join(directory, starter.filename)
      File.exists?(path).should be_true
      File.open(path, &.getb_to_end).should eq(Modeles::Starters.file(starter.kind, starter.locale, starter.format))
    end
  end
end
