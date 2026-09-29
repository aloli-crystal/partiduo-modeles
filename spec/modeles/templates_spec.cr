# SPDX-License-Identifier: AGPL-3.0-or-later

require "../spec_helper"

private alias S = Modeles::SpecSupport
private alias Api = Modeles::Api

private def upload(content : Bytes, filename = "facture.md", name = "Facture maison", kind = "invoice", locale = "fr",
                   template_id : Int64? = nil) : Partiduo::Api::Result(Api::TemplateView)
  Api.upload(S.actor, Api::UploadInput.new(filename: filename, content: content, name: name, kind: kind, locale: locale,
    template_id: template_id))
end

# Archive ODT réécrite avec `mimetype` en dernier et compressé : lisible,
# mais refusée par le contrôle de signature du socle des pièces jointes.
private def misordered_odt : Bytes
  source = Modeles::Starters.file("invoice", "fr", "odt")
  parts = Compress::Zip::File.open(IO::Memory.new(source)) do |zip|
    zip.entries.map { |entry| {entry.filename, entry.open(&.getb_to_end)} }
  end
  io = IO::Memory.new
  Compress::Zip::Writer.open(io) do |writer|
    parts.sort_by { |(name, _)| name == "mimetype" ? 1 : 0 }.each { |(name, data)| writer.add(name, data) }
  end
  io.to_slice
end

describe "Dépôt, contrôle et versions des modèles (ADR-010 D3)" do
  it "refuse, sans rien créer, un ODT dont l'archive n'a pas la signature exigée par le socle" do
    S.books
    result = upload(misordered_odt, filename: "facture.odt")
    result.success?.should be_false
    result.errors.map { |error| {error.field, error.key} }.should eq([{"content", "core.errors.attachment.content_type.mismatch"}])
    Modeles::Template.all.count.should eq(0)
    Modeles::StoredFile.all.count.should eq(0)
  end

  it "refuse un modèle incomplet avec la liste de ce qui manque" do
    S.books
    result = upload("# {{ facture.numero }}\n\n{{ client.nom }}".to_slice)
    result.failure?.should be_true
    keys = result.errors.map(&.key)
    keys.should contain("modeles.check.missing")
    missing = result.errors.compact_map(&.params["requirement"]?)
    missing.should contain("mentions")
    missing.should contain("lines")
    result.errors.all?(&.field.==("content")).should be_true
    Api.templates(S.actor).should be_empty
    Api.message(Api::IssueView.new(result.errors.first.key, result.errors.first.params)).should start_with("Mention obligatoire absente")
  end

  it "refuse un champ inconnu, une balise interdite, un format inconnu, un fichier vide" do
    S.books
    upload("{{ facture.numro }}".to_slice).errors.map(&.key).should contain("modeles.check.unknown_field")
    upload("{% include 'x' %}".to_slice).errors.map(&.key).should contain("modeles.check.tag_forbidden")
    upload("x".to_slice, filename: "modele.txt").errors.map(&.key).should eq(["modeles.check.format_unknown"])
    upload(Bytes.empty).errors.map(&.key).should eq(["modeles.check.empty"])
    upload("x".to_slice, name: "", kind: "order", locale: "de").errors.map(&.field).should eq(%w[name kind locale])
  end

  it "rend un rapport de contrôle sans rien enregistrer, remarque sur le PDF comprise" do
    S.books
    report = Api.check(S.actor, Api::UploadInput.new("facture.odt", Modeles::Starters.file("invoice", "fr", "odt"), kind: "invoice"))
    report.ok?.should be_true
    report.format.should eq("odt")
    report.fields.should contain("lignes.designation")
    report.pdf_available.should be_false
    report.warnings.map(&.key).should eq(["modeles.check.no_pdf"])
    S.fake_converters
    Api.check(S.actor, Api::UploadInput.new("facture.odt", Modeles::Starters.file("invoice", "fr", "odt"), kind: "invoice"))
      .warnings.should be_empty
  end

  it "enregistre une version, l'active après l'aperçu, puis garde les versions suivantes en attente" do
    S.books
    view = upload(Modeles::Starters.file("invoice", "fr", "markdown")).value!
    view.latest_version.should eq(1)
    view.active_version.should be_nil
    view.active?.should be_false
    view.versions.first.warnings.map(&.key).should eq(["modeles.check.no_pdf"])

    preview = Api.preview(S.reader, view.id).value!
    preview.rendition.should be_nil
    preview.draft.should be_true
    text = String.new(preview.file.content)
    text.should start_with("**Exemple — sans valeur**")
    text.should contain("F-EXEMPLE-0001")
    preview.file.filename.should eq("apercu-facture-maison-v1.md")

    Api.activate(S.actor, view.id).value!.active_version.should eq(1)
    second = upload(Modeles::Starters.file("invoice", "fr", "markdown"), template_id: view.id).value!
    second.latest_version.should eq(2)
    second.active_version.should eq(1)
    second.pending_version?.should be_true
    Api.activate(S.actor, view.id, 2).value!.active_version.should eq(2)
    Api.version_file(S.reader, view.id, 1).content.should eq(Modeles::Starters.file("invoice", "fr", "markdown"))
  end

  it "garde le format du modèle pour une nouvelle version et refuse un modèle retiré" do
    S.books
    view = S.template
    result = upload(Modeles::Starters.file("invoice", "fr", "docx"), filename: "f.docx", template_id: view.id)
    result.errors.map(&.key).should eq(["modeles.check.format_changed"])
    Api.retire(S.actor, view.id).value!.retired?.should be_true
    upload(Modeles::Starters.file("invoice", "fr", "markdown"), template_id: view.id).errors.map(&.key).should eq(["modeles.errors.template.retired"])
    Api.templates(S.actor).should be_empty
    Api.templates(S.actor, Api::TemplateQuery.new(include_retired: true)).map(&.id).should eq([view.id])
  end

  it "désigne un seul modèle par défaut par type de document et langue" do
    S.books
    first = S.template(name: "Premier")
    second = S.template(name: "Second", format: "asciidoc")
    Api.template(S.actor, first.id).is_default.should be_false
    Api.default_template(S.actor, "invoice", "fr").try(&.id).should eq(second.id)
    english = S.template(locale: "en", name: "English")
    Api.default_template(S.actor, "invoice", "en").try(&.id).should eq(english.id)
    Api.template(S.actor, second.id).is_default.should be_true
    Api.unset_default(S.actor, second.id).value!.is_default.should be_false
    Api.default_template(S.actor, "invoice", "fr").should be_nil
  end

  it "refuse de désigner par défaut un modèle qui n'est pas en service" do
    S.books
    view = upload(Modeles::Starters.file("invoice", "fr", "markdown")).value!
    Api.set_default(S.actor, view.id).errors.map(&.key).should eq(["modeles.errors.template.not_active"])
    Api.activate(S.actor, view.id).value!
    Api.set_default(S.actor, view.id).value!
    Api.retire(S.actor, view.id).value!.is_default.should be_false
  end
end
