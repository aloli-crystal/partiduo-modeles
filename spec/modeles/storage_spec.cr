# SPDX-License-Identifier: AGPL-3.0-or-later

require "../spec_helper"

private alias S = Modeles::SpecSupport

describe "Conservation des fichiers (ADR-010 D1, BLOCAGE B-MOD-001)" do
  it "conserve le texte et le PDF en pièces jointes du socle" do
    S.books
    file = Modeles::Files.store("facture.md", "text/markdown", "# Facture".to_slice)
    attachment = Partiduo::Api::Core.attachment(S::SYSTEM, (file.attachment_id || raise "pièce jointe absente").to_i64)
    attachment.content_type.should eq("text/plain")
    attachment.filename.should eq("facture.md")
    file.content_type.should eq("text/markdown")
    Modeles::Files.read(file).should eq("# Facture".to_slice)
    pdf = Modeles::Files.store("f.pdf", "application/pdf", "%PDF-1.4\n".to_slice)
    pdf.attachment_id.should_not be_nil
  end

  it "conserve ODT et DOCX dans le stockage de l'instance, empreinte vérifiée à la lecture" do
    S.books
    bytes = Modeles::Starters.file("invoice", "fr", "odt")
    file = Modeles::Files.store("facture.odt", Modeles::Config::CONTENT_TYPES["odt"], bytes)
    file.attachment_id.should be_nil
    name = file.storage_name || raise "fichier absent"
    name.should match(/\Amodeles\/\d{4}\/\d{2}\/[0-9a-f-]{36}\.odt\z/)
    Modeles::Files.read(file).should eq(bytes)
    file.sha256.should eq(Digest::SHA256.hexdigest(bytes))
    Marten.media_files_storage.delete(name)
    Marten.media_files_storage.save(name, IO::Memory.new("altéré"))
    expect_raises(Modeles::FileCorrupted) { Modeles::Files.read(file) }
  end

  it "efface le fichier écrit si la transaction est annulée" do
    S.books
    names = [] of String
    Marten::DB::Connection.default.transaction do
      Modeles::Files.store("f.docx", Modeles::Config::CONTENT_TYPES["docx"], "PK".to_slice).storage_name.try { |name| names << name }
      raise Marten::DB::Errors::Rollback.new
    end
    names.size.should eq(1)
    Marten.media_files_storage.exists?(names.first).should be_false
  end
end
