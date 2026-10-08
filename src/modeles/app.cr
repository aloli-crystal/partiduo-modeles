# SPDX-License-Identifier: AGPL-3.0-or-later

require "./manifest"
require "./config"
require "./models/**"
require "./fusion/**"
require "./office/**"
require "./services/**"
require "./starters/**"
require "./api/**"

# Extension MODELES de Partiduo (ADR-010) : modèles de documents déposés en
# AsciiDoc, Markdown, ODT ou DOCX, fusionnés avec un document de la
# Facturation. Même plan qu'une application du cœur : `manifest.cr`,
# `models/`, `migrations/`, `services/` (interne), `fusion/` (moteur de
# fusion), `office/` (archives ODT et DOCX), `starters/` (modèles de départ),
# `api/` (contrat public `Modeles::Api`), `locales/`.
module Modeles
  # Lue à la compilation dans `shard.yml`, seule source du numéro : chaque
  # commit y incrémente le dernier chiffre.
  VERSION = {{
              (read_file("#{__DIR__}/../../shard.yml")
                .lines
                .find(&.starts_with?("version:")) || "version: 0.0.0")
                .gsub(/^version:\s*/, "")
                .chomp
            }}

  # Code du registre (ADR-003 D2) : `modeles` dans `PARTIDUO_MODULES`.
  CODE = "MODELES"

  # Application Marten du métier : tables `modeles_*`, migrations, libellés.
  class App < Marten::App
    label "modeles"
  end

  # Applications Marten du métier, à ajouter à `installed_apps` de la
  # distribution après `Partiduo::INSTALLED_APPS`.
  INSTALLED_APPS = [Modeles::App] of Marten::Apps::Config.class
end
