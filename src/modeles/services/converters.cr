# SPDX-License-Identifier: AGPL-3.0-or-later

require "file_utils"
require "kramdown-asciidoc/kramdown_asciidoc"

module Modeles
  # Échec d'une conversion en PDF : `key`, clé de traduction
  # (`modeles.errors.pdf.<code>`), `detail` : message de l'outil.
  class ConversionError < Exception
    getter code : String
    getter detail : String

    def initialize(@code : String, @detail : String = "")
      super("conversion PDF : #{@code} #{@detail}".strip)
    end

    def key : String
      "modeles.errors.pdf.#{code}"
    end
  end

  # Conversion en PDF par des outils externes, facultatifs (ADR-010 D5) :
  #
  # [cols="1,2,2"]
  # |===
  # |Format |Outil |Variable de l'instance
  #
  # |AsciiDoc |`asciicrystal-pdf` (mode `secure`, thème embarqué) |`PARTIDUO_MODELES_ASCIICRYSTAL_PDF`
  # |Markdown |converti en AsciiDoc dans le processus (`kramdown-asciidoc`), puis `asciicrystal-pdf` |`PARTIDUO_MODELES_ASCIICRYSTAL_PDF`
  # |ODT, DOCX |LibreOffice sans interface (`soffice --headless --convert-to pdf`) |`PARTIDUO_MODELES_SOFFICE`
  # |===
  #
  # `asciicrystal-pdf` tourne dans son propre processus, et non comme
  # bibliothèque : il peut ainsi être tué au-delà du délai, et le
  # compilateur Crystal 1.19.1 échoue quand `asciicrystal` et une sous-classe
  # de `Hash` (celle de Marten) sont dans le même programme (doc/ETAT.adoc,
  # D-MOD-017).
  #
  # Chaque variable donne le chemin de l'outil ; `auto` le cherche dans le
  # `PATH` ; absente ou vide, le PDF du format est désactivé (et l'écran le
  # dit). `PARTIDUO_MODELES_CONVERT_TIMEOUT` : délai maximal en secondes
  # (60 par défaut). L'outil est lancé sans shell (tableau d'arguments),
  # dans un répertoire temporaire propre à la conversion, effacé ensuite ;
  # au-delà du délai, il est tué.
  module Converters
    DEFAULT_TIMEOUT = 60

    # Outil déclaré pour un format.
    record Tool, name : String, path : String, timeout : Time::Span

    VARIABLES = {
      "odt"      => {"PARTIDUO_MODELES_SOFFICE", "soffice"},
      "docx"     => {"PARTIDUO_MODELES_SOFFICE", "soffice"},
      "asciidoc" => {"PARTIDUO_MODELES_ASCIICRYSTAL_PDF", "asciicrystal-pdf"},
      "markdown" => {"PARTIDUO_MODELES_ASCIICRYSTAL_PDF", "asciicrystal-pdf"},
    }

    # Attributs d'un modèle AsciiDoc qui désigneraient des fichiers du
    # serveur (thème, polices) : leurs lignes sont retirées avant la
    # conversion.
    SERVER_PATH_ATTRIBUTES = /^:(pdf-theme|pdf-themesdir|pdf-fontsdir|pdf-theme-dir):[^\n]*\n?/m

    # Outils fixés par le code (specs, instance de démonstration) ; ils
    # remplacent la configuration de l'environnement. `nil` : désactivé.
    @@overrides = {} of String => Tool?

    def self.override(format : String, tool : Tool?) : Nil
      @@overrides[format] = tool
    end

    def self.reset : Nil
      @@overrides.clear
    end

    def self.timeout : Time::Span
      seconds = ENV["PARTIDUO_MODELES_CONVERT_TIMEOUT"]?.try(&.to_i?) || DEFAULT_TIMEOUT
      seconds.clamp(1, 3600).seconds
    end

    # Outil du format, s'il est déclaré et exécutable.
    def self.tool(format : String) : Tool?
      return @@overrides[format] if @@overrides.has_key?(format)
      variable, command = VARIABLES[format]? || return
      value = ENV[variable]?.try(&.strip).presence || return
      path = value == "auto" ? Process.find_executable(command) : value
      return unless path && File.file?(path) && File::Info.executable?(path)
      Tool.new(command, path, timeout)
    end

    def self.available?(format : String) : Bool
      !tool(format).nil?
    end

    # PDF du document `bytes` au format `format`. Lève `ConversionError`
    # (`unavailable`, `timeout`, `failed`).
    def self.convert(format : String, bytes : Bytes) : Bytes
      tool = tool(format) || raise ConversionError.new("unavailable")
      directory = File.join(Dir.tempdir, "partiduo-modeles-#{Random::Secure.hex(8)}")
      Dir.mkdir(directory, 0o700)
      begin
        extension = format == "markdown" ? "adoc" : Config::EXTENSIONS[format]
        input = File.join(directory, "document.#{extension}")
        output = File.join(directory, "document.pdf")
        File.write(input, source(format, bytes))
        run(tool, arguments(format, tool, directory, input, output), directory)
        pdf = File.exists?(output) ? File.open(output, &.getb_to_end) : Bytes.empty
        unless pdf.size > 5 && pdf[0, 5] == "%PDF-".to_slice
          raise ConversionError.new("failed", "aucun PDF produit")
        end
        pdf
      ensure
        FileUtils.rm_rf(directory)
      end
    end

    # Fichier remis à l'outil : le Markdown est converti en AsciiDoc ; un
    # AsciiDoc perd ses attributs qui désignent des fichiers du serveur.
    def self.source(format : String, bytes : Bytes) : Bytes
      case format
      when "markdown"
        KramdownAsciidoc.convert(String.new(bytes)).gsub(SERVER_PATH_ATTRIBUTES, "").to_slice
      when "asciidoc"
        String.new(bytes).gsub(SERVER_PATH_ATTRIBUTES, "").to_slice
      else
        bytes
      end
    end

    def self.arguments(format : String, tool : Tool, directory : String, input : String, output : String) : Array(String)
      case format
      when "odt", "docx"
        ["--headless", "--norestore", "--nolockcheck", "--nodefault", "--nologo",
         "-env:UserInstallation=file://#{directory}/profil", "--convert-to", "pdf", "--outdir", directory, input]
      else
        # `-N` : sans configuration personnelle ; `-n` : sans ouvrir le PDF ;
        # `-T fr` : thème embarqué, jamais un fichier désigné par le modèle.
        ["-N", "-n", "-T", "fr", "-a", "safe=secure", "-o", output, input]
      end
    end

    # Lance l'outil sans shell et attend au plus son délai ; le tue au-delà.
    private def self.run(tool : Tool, args : Array(String), directory : String) : Nil
      errors = IO::Memory.new
      process = Process.new(tool.path, args, chdir: directory, output: Process::Redirect::Close, error: errors,
        input: Process::Redirect::Close, env: {"HOME" => directory, "TMPDIR" => directory})
      finished = Channel(Process::Status).new(1)
      spawn { finished.send(process.wait) }
      select
      when status = finished.receive
        unless status.success?
          raise ConversionError.new("failed", errors.to_s.lines.last(3).join(" ").strip)
        end
      when timeout(tool.timeout)
        process.signal(Signal::KILL) rescue nil
        raise ConversionError.new("timeout", tool.timeout.total_seconds.to_i.to_s)
      end
    rescue error : File::Error | IO::Error
      raise ConversionError.new("failed", error.message.to_s)
    end
  end
end
