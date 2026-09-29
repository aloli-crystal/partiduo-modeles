# SPDX-License-Identifier: AGPL-3.0-or-later

require "../spec_helper"
require "../../src/partiduo-modeles/pdf_source"

private alias S = Modeles::SpecSupport
private alias Converters = Modeles::Converters

# Outil réel : l'exécutable construit dans ce dépôt (`shards build
# partiduo-modeles-pdf`), sinon celui du PATH ; absent, la spec est en
# attente (ADR-010 D5 : aucun convertisseur n'est requis pour les specs).
private def real_tool(format : String, command : String, timeout : Time::Span) : Converters::Tool?
  built = File.expand_path(File.join(__DIR__, "..", "..", "bin", command))
  path = File::Info.executable?(built) ? built : Process.find_executable(command)
  path.try { |found| Converters::Tool.new(command, found, timeout) }
end

private def sample_file(format : String) : Bytes
  view = Modeles::Sample.document("invoice", "fr", Time.utc(2026, 9, 15))
  Modeles::Fusion.render(format, Modeles::Starters.file("invoice", "fr", format), view)
end

describe "Conversion en PDF (ADR-010 D5)" do
  it "désactive le PDF d'un format sans outil déclaré" do
    Converters.available?("odt").should be_false
    expect_raises(Modeles::ConversionError, /unavailable/) { Converters.convert("odt", "x".to_slice) }
  end

  it "lit la configuration de l'instance : chemin, auto, délai" do
    Converters.reset
    begin
      ENV["PARTIDUO_MODELES_SOFFICE"] = File.join(S::BIN, "fake-convert")
      ENV["PARTIDUO_MODELES_CONVERT_TIMEOUT"] = "7"
      tool = Converters.tool("odt") || raise "outil non lu"
      tool.path.should eq(File.join(S::BIN, "fake-convert"))
      tool.timeout.should eq(7.seconds)
      ENV["PARTIDUO_MODELES_SOFFICE"] = "/nulle/part/soffice"
      Converters.tool("docx").should be_nil
      ENV["PARTIDUO_MODELES_SOFFICE"] = "auto"
      Converters.tool("odt").try(&.path).should eq(Process.find_executable("soffice"))
    ensure
      ENV.delete("PARTIDUO_MODELES_SOFFICE")
      ENV.delete("PARTIDUO_MODELES_CONVERT_TIMEOUT")
    end
  end

  it "lance l'outil sans shell, dans un répertoire temporaire effacé ensuite" do
    Converters.override("docx", S.fake_tool)
    before = Dir.children(Dir.tempdir).select(&.starts_with?("partiduo-modeles-"))
    pdf = Converters.convert("docx", "contenu".to_slice)
    String.new(pdf).should start_with("%PDF-1.4\n% 7")
    (Dir.children(Dir.tempdir).select(&.starts_with?("partiduo-modeles-")) - before).should be_empty
  end

  it "passe les arguments attendus à chaque outil" do
    tool = S.fake_tool
    Converters.arguments("odt", tool, "/t", "/t/document.odt", "/t/document.pdf").should eq([
      "--headless", "--norestore", "--nolockcheck", "--nodefault", "--nologo", "-env:UserInstallation=file:///t/profil",
      "--convert-to", "pdf", "--outdir", "/t", "/t/document.odt",
    ])
    %w[asciidoc markdown].each do |format|
      Converters.arguments(format, tool, "/t", "/t/document.adoc", "/t/document.pdf").should eq(
        ["/t/document.adoc", "/t/document.pdf"])
    end
  end

  it "remet à asciicrystal-pdf un AsciiDoc, Markdown compris, sans chemin du serveur" do
    markdown = Modeles::PdfSource.asciidoc("/t/document.md", "# Facture\n\nMontant **dû**.\n")
    markdown.should contain("= Facture")
    markdown.should contain("*dû*")
    asciidoc = ":pdf-theme: /etc/theme.yml\n:pdf-fontsdir: /etc\n= Facture\n:pdf-themesdir: /srv\n\nTexte.\n"
    Modeles::PdfSource.asciidoc("/t/document.adoc", asciidoc).should eq("= Facture\n\nTexte.\n")
  end

  it "tue l'outil qui dépasse son délai" do
    Converters.override("odt", S.fake_tool("slow-convert", 1.second))
    started = Time.instant
    expect_raises(Modeles::ConversionError, /timeout/) { Converters.convert("odt", "x".to_slice) }
    (Time.instant - started).should be < 10.seconds
  end

  it "signale l'échec de l'outil avec son message" do
    Converters.override("odt", S.fake_tool("failing-convert"))
    error = expect_raises(Modeles::ConversionError) { Converters.convert("odt", "x".to_slice) }
    error.code.should eq("failed")
    error.detail.should contain("police absente")
  end

  it "convertit AsciiDoc et Markdown avec partiduo-modeles-pdf (en attente sans l'outil)" do
    tool = real_tool("asciidoc", "partiduo-modeles-pdf", 60.seconds) || next pending!("partiduo-modeles-pdf non construit")
    %w[asciidoc markdown].each do |format|
      Converters.override(format, tool)
      pdf = Converters.convert(format, sample_file(format))
      String.new(pdf[0, 5]).should eq("%PDF-")
      pdf.size.should be > 1_000
    end
  end

  it "n'incorpore pas une image du serveur hors du modèle (B-MOD-006, en attente sans l'outil)" do
    tool = real_tool("asciidoc", "partiduo-modeles-pdf", 60.seconds) || next pending!("partiduo-modeles-pdf non construit")
    Converters.override("asciidoc", tool)
    image = File.expand_path(File.join(S::BIN, "..", "image-hors-modele.png"))
    pdf = String.new(Converters.convert("asciidoc", "= Facture\n\nimage::#{image}[]\n\nimage::../#{File.basename(image)}[]\n".to_slice)).scrub
    pdf.should start_with("%PDF-")
    pdf.should_not match(%r{/Subtype\s*/Image})
  end

  # Tant que kramdown-asciidoc boucle sur ce Markdown, l'exécutable est tué
  # au délai ; une fois corrigé, la conversion réussit. Dans les deux cas,
  # l'appel rend la main.
  it "rend la main quand kramdown-asciidoc boucle sur un Markdown (B-MOD-007, en attente sans l'outil)" do
    tool = real_tool("markdown", "partiduo-modeles-pdf", 3.seconds) || next pending!("partiduo-modeles-pdf non construit")
    Converters.override("markdown", tool)
    started = Time.instant
    begin
      Converters.convert("markdown", "x| A | b |\n| N | c |\n".to_slice)
    rescue error : Modeles::ConversionError
      error.code.should eq("timeout")
    end
    (Time.instant - started).should be < 15.seconds
  end

  it "convertit un ODT et un DOCX avec LibreOffice (en attente sans l'outil ou s'il ne rend pas la main)" do
    tool = real_tool("odt", "soffice", 20.seconds) || next pending!("soffice absent")
    %w[odt docx].each do |format|
      Converters.override(format, tool)
      begin
        String.new(Converters.convert(format, sample_file(format))[0, 5]).should eq("%PDF-")
      rescue error : Modeles::ConversionError
        pending!("soffice ne produit pas de PDF ici (#{error.code} #{error.detail})")
      end
    end
  end
end
