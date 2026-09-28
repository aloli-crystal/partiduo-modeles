# SPDX-License-Identifier: AGPL-3.0-or-later

require "../spec_helper"

private alias S = Modeles::SpecSupport
private alias Converters = Modeles::Converters

# Outil réel trouvé dans le PATH, sinon la spec est en attente (ADR-010 D5 :
# aucun convertisseur n'est requis pour les specs).
private def real_tool(format : String, command : String, timeout : Time::Span) : Converters::Tool?
  Process.find_executable(command).try { |path| Converters::Tool.new(command, path, timeout) }
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
      ENV["PARTIDUO_MODELES_PANDOC"] = File.join(S::BIN, "fake-convert")
      ENV["PARTIDUO_MODELES_CONVERT_TIMEOUT"] = "7"
      tool = Converters.tool("markdown") || raise "outil non lu"
      tool.path.should eq(File.join(S::BIN, "fake-convert"))
      tool.timeout.should eq(7.seconds)
      ENV["PARTIDUO_MODELES_PANDOC"] = "/nulle/part/pandoc"
      Converters.tool("markdown").should be_nil
      ENV["PARTIDUO_MODELES_PANDOC"] = "auto"
      Converters.tool("markdown").try(&.path).should eq(Process.find_executable("pandoc"))
    ensure
      ENV.delete("PARTIDUO_MODELES_PANDOC")
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
    Converters.arguments("asciidoc", tool, "/t", "/t/document.adoc", "/t/document.pdf").should eq(
      ["-S", "secure", "-a", "allow-uri-read!", "-o", "/t/document.pdf", "/t/document.adoc"])
    engine = tool.copy_with(engine: "weasyprint")
    Converters.arguments("markdown", engine, "/t", "/t/document.md", "/t/document.pdf").should eq(
      ["--pdf-engine=weasyprint", "--sandbox", "--from", "markdown", "-o", "/t/document.pdf", "/t/document.md"])
  end

  it "tue l'outil qui dépasse son délai" do
    Converters.override("odt", S.fake_tool("slow-convert", 1.second))
    started = Time.instant
    expect_raises(Modeles::ConversionError, /timeout/) { Converters.convert("odt", "x".to_slice) }
    (Time.instant - started).should be < 10.seconds
  end

  it "signale l'échec de l'outil avec son message" do
    Converters.override("markdown", S.fake_tool("failing-convert"))
    error = expect_raises(Modeles::ConversionError) { Converters.convert("markdown", "x".to_slice) }
    error.code.should eq("failed")
    error.detail.should contain("police absente")
  end

  it "convertit un Markdown avec pandoc (en attente sans pandoc ni moteur PDF)" do
    tool = real_tool("markdown", "pandoc", 60.seconds) || next pending!("pandoc absent")
    Converters.override("markdown", tool)
    begin
      String.new(Converters.convert("markdown", sample_file("markdown"))[0, 5]).should eq("%PDF-")
    rescue error : Modeles::ConversionError
      pending!("pandoc sans moteur PDF utilisable : #{error.detail}")
    end
  end

  it "convertit un AsciiDoc avec asciidoctor-pdf (en attente sans l'outil)" do
    tool = real_tool("asciidoc", "asciidoctor-pdf", 60.seconds) || next pending!("asciidoctor-pdf absent")
    Converters.override("asciidoc", tool)
    String.new(Converters.convert("asciidoc", sample_file("asciidoc"))[0, 5]).should eq("%PDF-")
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
