# SPDX-License-Identifier: AGPL-3.0-or-later

require "file_utils"

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
  # |AsciiDoc |`partiduo-modeles-pdf` (asciicrystal-pdf, mode `secure`, thème embarqué) |`PARTIDUO_MODELES_PDF`
  # |Markdown |`partiduo-modeles-pdf`, qui le convertit d'abord en AsciiDoc (`kramdown-asciidoc`) |`PARTIDUO_MODELES_PDF`
  # |ODT, DOCX |LibreOffice sans interface (`soffice --headless --convert-to pdf`) |`PARTIDUO_MODELES_SOFFICE`
  # |===
  #
  # `partiduo-modeles-pdf` est l'exécutable de ce shard (cible du même nom) :
  # il tourne dans son propre processus, conversion du Markdown comprise,
  # pour pouvoir être tué au-delà du délai, et pour qu'un modèle déposé par
  # l'utilisateur n'atteigne pas le serveur (D-MOD-017).
  #
  # Chaque variable donne le chemin de l'outil ; `auto` le cherche à côté de
  # l'exécutable du serveur, puis dans le `PATH` ; absente ou vide, le PDF
  # du format est désactivé (et l'écran le dit).
  # `PARTIDUO_MODELES_CONVERT_TIMEOUT` : délai maximal en secondes
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
      "asciidoc" => {"PARTIDUO_MODELES_PDF", "partiduo-modeles-pdf"},
      "markdown" => {"PARTIDUO_MODELES_PDF", "partiduo-modeles-pdf"},
    }

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
      path = value == "auto" ? find(command) : value
      return unless path && File.file?(path) && File::Info.executable?(path)
      Tool.new(command, path, timeout)
    end

    # `auto` : à côté de l'exécutable du serveur (où la distribution dépose
    # `partiduo-modeles-pdf`), sinon dans le `PATH`.
    def self.find(command : String) : String?
      if server = Process.executable_path
        sibling = File.join(File.dirname(server), command)
        return sibling if File.file?(sibling) && File::Info.executable?(sibling)
      end
      Process.find_executable(command)
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
        input = File.join(directory, "document.#{Config::EXTENSIONS[format]}")
        output = File.join(directory, "document.pdf")
        File.write(input, bytes)
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

    def self.arguments(format : String, tool : Tool, directory : String, input : String, output : String) : Array(String)
      case format
      when "odt", "docx"
        ["--headless", "--norestore", "--nolockcheck", "--nodefault", "--nologo",
         "-env:UserInstallation=file://#{directory}/profil", "--convert-to", "pdf", "--outdir", directory, input]
      else
        # Mode `secure` et thème embarqué sont fixés dans l'exécutable,
        # jamais passés par ici (src/partiduo-modeles/pdf.cr).
        [input, output]
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
