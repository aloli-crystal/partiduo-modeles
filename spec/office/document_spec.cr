# SPDX-License-Identifier: AGPL-3.0-or-later

require "../spec_helper"

private alias Files = Modeles::SpecSupport::OfficeFiles

private def sample(kind = "invoice", locale = "fr") : Partiduo::Api::Invoicing::DocumentView
  Modeles::Sample.document(kind, locale, Time.utc(2026, 9, 15))
end

describe "Modèles ODT et DOCX (ADR-010 D2)" do
  it "contrôle un DOCX dont les champs sont coupés en fragments" do
    report = Modeles::Fusion.analyze("docx", Files.invoice_docx, "invoice")
    report.errors.should eq([] of Modeles::Fusion::Issue)
    report.printed.should contain("facture.numero")
    report.loops.should contain("lignes")
  end

  it "fusionne un DOCX : lignes répétées, champs réunis, valeurs échappées, XML bien formé" do
    view = sample
    view = view.copy_with(customer: view.customer.copy_with(name: "Durand & Fils <SARL>"))
    bytes = Modeles::Fusion.render("docx", Files.invoice_docx, view)
    xml = Files.part(bytes, "word/document.xml")
    XML.parse(xml).should be_truthy
    xml.should_not contain("{{")
    xml.should_not contain("{%")
    xml.should contain("Durand &amp; Fils &lt;SARL&gt;")
    text = Files.visible(xml)
    text.should contain("Facture F-EXEMPLE-0001")
    text.should contain("Conseil en organisation\nAtelier d'une demi-journée")
    text.should contain("Frais de déplacement")
    xml.scan("<w:tr>").size.should eq(1 + 4) # en-tête + quatre lignes
    text.should_not contain("Acompte :")
    text.should contain("Indemnité forfaitaire")
    xml.should contain("<w:br/>")
  end

  it "fusionne un ODT : lignes répétées, en-tête des pages maîtresses, mimetype conservé" do
    footer = Files.tp("{{ vendeur.nom }} · SIREN {{ vendeur.siren }}")
    bytes = Modeles::Fusion.render("odt", Files.odt(Files.invoice_odt_body, footer), sample)
    Modeles::Office::Package.read(bytes).names.first.should eq("mimetype")
    content = Files.part(bytes, "content.xml")
    XML.parse(content).should be_truthy
    content.scan("<table:table-row>").size.should eq(1 + 4)
    Files.visible(content).should contain("Facture F-EXEMPLE-0001")
    content.should contain("<text:line-break/>")
    Files.visible(Files.part(bytes, "styles.xml")).should contain("Atelier Exemple SARL · SIREN 123456789")
  end

  it "fusionne les en-têtes d'un DOCX" do
    bytes = Files.docx(Files.para(Files.r("{{ facture.numero }}")), header: Files.para(Files.r("{{ vendeur.nom }}")))
    Files.visible(Files.part(Modeles::Fusion.render("docx", bytes, sample), "word/header1.xml")).should eq("Atelier Exemple SARL")
  end

  it "ajoute la mention d'un rendu sans valeur en tête du corps" do
    docx = Modeles::Fusion.render("docx", Files.invoice_docx, sample, "Brouillon — sans valeur")
    Files.visible(Files.part(docx, "word/document.xml")).lstrip.should start_with("Brouillon — sans valeur")
    odt = Modeles::Fusion.render("odt", Files.invoice_odt, sample, "Brouillon — sans valeur")
    Files.visible(Files.part(odt, "content.xml")).lstrip.should start_with("Brouillon — sans valeur")
  end

  it "refuse un fichier qui n'est pas du format annoncé" do
    Modeles::Fusion.analyze("odt", Files.invoice_docx, "invoice").errors.map(&.code).should eq(["invalid_package"])
    Modeles::Fusion.analyze("docx", "texte".to_slice).errors.map(&.code).should eq(["invalid_package"])
  end

  it "signale une mention obligatoire absente d'un ODT" do
    bytes = Files.odt(Files.tp("{{ facture.numero }}"))
    codes = Modeles::Fusion.analyze("odt", bytes, "quote").errors.map { |issue| issue.params["requirement"]? }
    codes.should contain("mentions")
    codes.should contain("lines")
  end
end
