# SPDX-License-Identifier: AGPL-3.0-or-later

require "kramdown-asciidoc/kramdown_asciidoc"

module Modeles
  # Source AsciiDoc remise à asciicrystal-pdf par l'exécutable
  # `partiduo-modeles-pdf` (D-MOD-017). Tout se fait dans son processus, sous
  # le délai de `Modeles::Converters` : `kramdown-asciidoc` peut boucler sans
  # fin sur un Markdown (B-MOD-007), et ne doit pas bloquer le serveur.
  module PdfSource
    # Attributs d'un modèle AsciiDoc qui désigneraient des fichiers du
    # serveur (thème, polices) : leurs lignes sont retirées.
    SERVER_PATH_ATTRIBUTES = /^:(pdf-theme|pdf-themesdir|pdf-fontsdir|pdf-theme-dir):[^\n]*\n?/m

    # AsciiDoc du fichier `path` de contenu `text` : un Markdown (`.md`) est
    # d'abord converti en AsciiDoc.
    def self.asciidoc(path : String, text : String) : String
      text = KramdownAsciidoc.convert(text) if path.ends_with?(".md")
      text.gsub(SERVER_PATH_ATTRIBUTES, "")
    end
  end
end
