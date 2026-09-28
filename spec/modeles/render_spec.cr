# SPDX-License-Identifier: AGPL-3.0-or-later

require "../spec_helper"

private alias S = Modeles::SpecSupport
private alias Api = Modeles::Api
private alias Inv = Partiduo::Api::Invoicing

describe "Rendu d'un document avec un modèle (ADR-010 D4)" do
  it "rend une facture émise avec le modèle par défaut et conserve le rendu" do
    S.books
    template = S.template(format: "docx")
    invoice = S.issue
    result = Api.render(S.reader, invoice.id, pdf: false).value!
    rendition = (result.rendition || raise "rendu non conservé")
    rendition.document_id.should eq(invoice.id)
    rendition.document_number.should eq(invoice.number)
    rendition.template_id.should eq(template.id)
    rendition.version_number.should eq(1)
    rendition.format.should eq("docx")
    rendition.pdf?.should be_false
    rendition.pdf_error.should eq("")
    rendition.sha256.should eq(Digest::SHA256.hexdigest(result.file.content))
    rendition.filename.should eq("#{invoice.number.to_s.downcase}-modele-docx-v1.docx")

    stored = Api.rendition_file(S.reader, rendition.id)
    stored.content.should eq(result.file.content)
    stored.content_type.should eq(Modeles::Config::CONTENT_TYPES["docx"])
    xml = S::OfficeFiles.part(stored.content, "word/document.xml")
    text = S::OfficeFiles.visible(xml)
    text.should contain(invoice.number.to_s)
    text.should contain("Durand & Fils <SARL>")
    text.should contain("Conseil *urgent* | analyse")
    text.should contain("SIREN du client : 552100554")
    text.should contain("FR7630006000011234567890189")
    Api.renditions(S.reader, invoice.id).map(&.id).should eq([rendition.id])
  end

  it "ne modifie jamais la facture : numéro, montants, empreinte" do
    S.books
    S.template
    invoice = S.issue
    Api.render(S.reader, invoice.id).value!
    after = Inv.document(S::SYSTEM, invoice.id)
    after.number.should eq(invoice.number)
    after.totals.should eq(invoice.totals)
    after.fingerprint.should eq(invoice.fingerprint)
    after.updated_at.should eq(invoice.updated_at)
    Inv.verify_fingerprint(S::SYSTEM, invoice.id).should be_true
    Inv.document_events(S::SYSTEM, invoice.id).map(&.action).should_not contain("updated")
  end

  it "produit et conserve le PDF quand le convertisseur est déclaré" do
    S.books
    S.template(format: "odt")
    S.fake_converters
    invoice = S.issue
    result = Api.render(S.reader, invoice.id).value!
    pdf = result.pdf || raise "PDF absent"
    String.new(pdf.content).should start_with("%PDF-")
    rendition = (result.rendition || raise "rendu non conservé")
    rendition.pdf_sha256.should eq(Digest::SHA256.hexdigest(pdf.content))
    Api.rendition_file(S.reader, rendition.id, "pdf").content.should eq(pdf.content)
  end

  it "conserve le fichier et note l'échec quand la conversion échoue" do
    S.books
    S.template(format: "asciidoc")
    S.fake_converters("failing-convert")
    result = Api.render(S.reader, S.issue.id).value!
    result.pdf.should be_nil
    result.pdf_error.should eq("modeles.errors.pdf.failed")
    result.pdf_detail.should contain("police absente")
    (result.rendition || raise "rendu non conservé").pdf_error.should eq("modeles.errors.pdf.failed")
    expect_raises(Partiduo::Api::NotFound) { Api.rendition_file(S.reader, (result.rendition || raise "rendu non conservé").id, "pdf") }
  end

  it "rend un brouillon en aperçu marqué et ne le conserve pas" do
    S.books
    S.template(format: "markdown")
    draft = S.draft
    result = Api.render(S.reader, draft.id).value!
    result.draft.should be_true
    result.rendition.should be_nil
    text = String.new(result.file.content)
    text.should start_with("**Brouillon — sans valeur**")
    text.should contain("# Facture Brouillon — sans valeur")
    result.file.filename.should eq("brouillon-#{draft.id}.md")
    Api.renditions(S.reader).should be_empty
  end

  it "rend un devis et un avoir avec les modèles de leur type" do
    S.books
    S.template("quote", format: "asciidoc")
    S.template("credit_note", format: "odt")
    quote = S.issue("quote")
    text = String.new(Api.render(S.reader, quote.id).value!.file.content)
    text.should contain("= Devis #{quote.number}")
    invoice = S.issue
    credit = S.issue("credit_note", credited: invoice.id, customer_id: invoice.customer_card_id)
    odt = Api.render(S.reader, credit.id).value!.file.content
    S::OfficeFiles.visible(S::OfficeFiles.part(odt, "content.xml")).should contain(invoice.number.to_s)
  end

  it "présente montants et dates dans la langue du document" do
    S.books
    S.template(locale: "en", format: "markdown")
    invoice = S.issue(locale: "en")
    text = String.new(Api.render(S.reader, invoice.id).value!.file.content)
    text.should contain("| Date | 2026-09-15 |")
    text.should contain("| Description | Qty |")
    text.should match(/\| \d{1,3}(,\d{3})*\.\d{2} EUR \|/)
  end

  it "refuse un document sans modèle, un modèle d'un autre type ou pas en service" do
    S.books
    invoice = S.issue
    Api.render(S.reader, invoice.id).errors.map(&.key).should eq(["modeles.errors.template.none"])
    quote_template = S.template("quote")
    Api.render(S.reader, invoice.id, quote_template.id).errors.map(&.key).should eq(["modeles.errors.template.kind_mismatch"])
    pending = Api.upload(S.actor, Api::UploadInput.new("f.md", Modeles::Starters.file("invoice", "fr", "markdown"), name: "p",
      kind: "invoice", locale: "fr")).value!
    Api.render(S.reader, invoice.id, pending.id).errors.map(&.key).should eq(["modeles.errors.template.not_active"])
  end

  it "rend avec la version en service et garde la version de chaque rendu" do
    S.books
    template = S.template
    invoice = S.issue
    first = Api.render(S.reader, invoice.id).value!.rendition || raise "rendu non conservé"
    changed = String.new(Modeles::Starters.file("invoice", "fr", "markdown")).sub("# ", "# Version 2 · ")
    Api.upload(S.actor, Api::UploadInput.new("f.md", changed.to_slice, template_id: template.id)).value!
    Api.activate(S.actor, template.id).value!
    second = Api.render(S.reader, invoice.id).value!.rendition || raise "rendu non conservé"
    second.version_number.should eq(2)
    String.new(Api.rendition_file(S.reader, second.id).content).should start_with("# Version 2 · ")
    Api.rendition(S.reader, first.id).version_number.should eq(1)
    String.new(Api.rendition_file(S.reader, first.id).content).should start_with("# Facture ")
  end

  it "propose d'abord le modèle par défaut de la langue du document" do
    S.books
    other = S.template(name: "Autre", format: "asciidoc", default: false)
    default = S.template(name: "Défaut")
    english = S.template(locale: "en", name: "English")
    Api.templates_for(S.reader, S.issue.id).map(&.id).should eq([default.id, other.id, english.id])
  end
end
