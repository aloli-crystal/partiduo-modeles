# SPDX-License-Identifier: AGPL-3.0-or-later

# Exécutable `partiduo-modeles-pdf` : PDF d'un AsciiDoc (`.adoc`) ou d'un
# Markdown (`.md`, converti en AsciiDoc) par asciicrystal-pdf, lancé en
# processus séparé par `Modeles::Converters` (délai, arrêt forcé, isolation
# d'un modèle déposé par l'utilisateur ; D-MOD-017).
#
#   partiduo-modeles-pdf ENTRÉE.adoc|ENTRÉE.md SORTIE.pdf
#
# Les réglages ne viennent que d'ici, jamais de l'appelant ni du modèle :
# mode `secure` (ni inclusion, ni lecture d'adresse), thème embarqué `fr`,
# sans configuration personnelle. Ce programme ne requiert ni le cœur ni
# Marten : il reste petit, et hors d'atteinte du bogue du compilateur
# qu'y déclenchait une sous-classe de Hash (crystal-lang/crystal#17507).
require "asciicrystal-pdf"
require "./pdf_source"

unless ARGV.size == 2
  STDERR.puts "Usage : partiduo-modeles-pdf ENTRÉE.adoc|ENTRÉE.md SORTIE.pdf"
  exit 2
end

input, output = ARGV[0], ARGV[1]
begin
  source = Modeles::PdfSource.asciidoc(input, File.read(input))
  # Mêmes options que `Asciicrystal.load_file`, sur la source convertie.
  path = File.expand_path(input)
  document = Asciicrystal.load(source, {
    "docfile" => path, "docdir" => File.dirname(path), "docname" => File.basename(path, File.extname(path)),
    "docfilesuffix" => File.extname(path), "outfile" => output, "safe" => "secure",
  })
  AsciicrystalPDF::Converter.new("pdf", AsciicrystalPDF::ThemeLoader.resolve("fr")).convert(document)
rescue error
  STDERR.puts "partiduo-modeles-pdf : #{error.message}"
  exit 1
end
