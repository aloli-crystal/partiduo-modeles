# SPDX-License-Identifier: AGPL-3.0-or-later

# Écrit les modèles de départ (ADR-010 D6) dans `starters/` : facture, devis
# et avoir, en AsciiDoc, Markdown, ODT et DOCX, en français, en anglais et
# en néerlandais. Ils sont produits par `Modeles::Starters` (le même code
# que le téléchargement depuis l'écran) ; les archives ODT et DOCX sont
# identiques d'une génération à l'autre, et une spec vérifie que le
# dossier est à jour.
#
# `crystal run scripts/starters.cr`
ENV["MARTEN_ENV"] ||= "test"

require "partiduo-ui-bulma/partiduo_ui"
require "../src/partiduo-modeles"
require "../ui/bulma/bulma"
require "../config/settings/base"
require "../config/settings/**"

Marten.setup

directory = File.expand_path("../starters", __DIR__)
Dir.mkdir_p(directory)
Modeles::Starters.list.each do |starter|
  path = File.join(directory, starter.filename)
  File.write(path, Modeles::Starters.file(starter.kind, starter.locale, starter.format))
  puts "#{path.lchop(File.expand_path("..", __DIR__) + "/")} (#{File.size(path)} octets)"
end
