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

# Polices livrées à côté de l'exécutable (archive de `partiduo-fleet build`,
# `share/partiduo-modeles-pdf/fonts`), sinon celles du répertoire de
# construction : asciicrystal-pdf fixe leur chemin à la compilation, et
# retombe sans rien dire sur les polices standard du PDF s'il ne les trouve
# pas (moins de caractères, autre rendu).
def theme : AsciicrystalPDF::Theme
  theme = AsciicrystalPDF::ThemeLoader.resolve("fr")
  executable = Process.executable_path || return theme
  fonts = File.expand_path(File.join(File.dirname(executable), "..", "share", "partiduo-modeles-pdf", "fonts"))
  return theme unless Dir.exists?(fonts)
  shipped = ->(path : String?) do
    path && path.starts_with?(AsciicrystalPDF::FONTS_DIR) ? File.join(fonts, File.basename(path)) : path
  end
  theme.base_font_path = shipped.call(theme.base_font_path)
  theme.base_font_bold_path = shipped.call(theme.base_font_bold_path)
  theme.base_font_italic_path = shipped.call(theme.base_font_italic_path)
  theme.base_font_bold_italic_path = shipped.call(theme.base_font_bold_italic_path)
  theme.mono_font_path = shipped.call(theme.mono_font_path)
  theme.mono_font_bold_path = shipped.call(theme.mono_font_bold_path)
  theme
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
  AsciicrystalPDF::Converter.new("pdf", theme).convert(document)
rescue error
  STDERR.puts "partiduo-modeles-pdf : #{error.message}"
  exit 1
end
