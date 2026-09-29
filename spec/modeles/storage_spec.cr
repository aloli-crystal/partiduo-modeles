# SPDX-License-Identifier: AGPL-3.0-or-later

require "../spec_helper"

private alias S = Modeles::SpecSupport

# Nom du fichier d'une pièce jointe dans le stockage de l'instance (lu en
# base : le contrat du socle ne l'expose pas).
private def storage_name(file : Modeles::StoredFile) : String
  Marten::DB::Connection.default.open do |db|
    db.scalar("SELECT storage_name FROM core_attachment WHERE id = $1", file.attachment_id!).as(String)
  end
end

describe "Conservation des fichiers par le socle des pièces jointes (ADR-010 D1)" do
  it "conserve le texte et le PDF en pièces jointes du socle" do
    S.books
    file = Modeles::Files.store("facture.md", "text/markdown", "# Facture".to_slice)
    attachment = Partiduo::Api::Core.attachment(S::SYSTEM, file.attachment_id!.to_i64)
    attachment.content_type.should eq("text/plain")
    attachment.filename.should eq("facture.md")
    file.content_type.should eq("text/markdown")
    Modeles::Files.read(file).should eq("# Facture".to_slice)
    pdf = Modeles::Files.store("f.pdf", "application/pdf", "%PDF-1.4\n".to_slice)
    Partiduo::Api::Core.attachment(S::SYSTEM, pdf.attachment_id!.to_i64).content_type.should eq("application/pdf")
  end

  it "conserve ODT et DOCX en pièces jointes du socle, sous leur type, empreinte vérifiée à la lecture" do
    S.books
    {"odt", "docx"}.each do |format|
      bytes = Modeles::Starters.file("invoice", "fr", format)
      content_type = Modeles::Config::CONTENT_TYPES[format]
      file = Modeles::Files.store("facture.#{format}", content_type, bytes)
      attachment = Partiduo::Api::Core.attachment(S::SYSTEM, file.attachment_id!.to_i64)
      attachment.content_type.should eq(content_type)
      attachment.sha256.should eq(Digest::SHA256.hexdigest(bytes))
      storage_name(file).should end_with(".#{format}")
      Modeles::Files.read(file).should eq(bytes)
      file.sha256.should eq(Digest::SHA256.hexdigest(bytes))
    end
  end

  it "signale un fichier altéré dans le stockage" do
    S.books
    file = Modeles::Files.store("facture.odt", Modeles::Config::CONTENT_TYPES["odt"], Modeles::Starters.file("invoice", "fr", "odt"))
    name = storage_name(file)
    Marten.media_files_storage.delete(name)
    Marten.media_files_storage.save(name, IO::Memory.new("altéré"))
    expect_raises(Modeles::FileCorrupted) { Modeles::Files.read(file) }
  end

  it "remonte le refus du socle pour une archive qui n'a pas la signature de son type" do
    S.books
    error = expect_raises(Modeles::StorageRefused) do
      Modeles::Files.store("f.docx", Modeles::Config::CONTENT_TYPES["docx"], "PK\u0003\u0004 pas une archive".to_slice)
    end
    error.errors.map(&.key).should eq(["core.errors.attachment.content_type.mismatch"])
  end

  it "n'écrit rien si la transaction est annulée" do
    S.books
    Marten::DB::Connection.default.transaction do
      Modeles::Files.store("f.docx", Modeles::Config::CONTENT_TYPES["docx"], Modeles::Starters.file("quote", "fr", "docx"))
      raise Marten::DB::Errors::Rollback.new
    end
    Modeles::StoredFile.all.count.should eq(0)
  end
end
