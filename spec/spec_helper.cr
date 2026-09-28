# SPDX-License-Identifier: AGPL-3.0-or-later

ENV["MARTEN_ENV"] = "test"
# La Facturation seule (dépendance de l'extension).
ENV["PARTIDUO_MODULES"] ||= "invoicing"
# Aucun convertisseur déclaré par l'environnement : les specs les fixent.
%w[PARTIDUO_MODELES_SOFFICE PARTIDUO_MODELES_ASCIIDOCTOR_PDF PARTIDUO_MODELES_PANDOC].each { |name| ENV.delete(name) }

require "spec"

# Composition d'une distribution : l'interface (qui charge le cœur), le
# métier de l'extension, son interface Bulma, puis les réglages.
require "partiduo-ui-bulma/partiduo_ui"
require "../src/partiduo-modeles"
require "../ui/bulma/bulma"
require "../config/settings/base"
require "../config/settings/**"
# Migrations du cœur et de l'extension.
require "partiduo/cli"
require "../src/partiduo-modeles/cli"

require "marten/spec"
require "marten_auth/spec"

# Comptes, navigateur et dossier de test de l'interface, créés par le
# contrat `Partiduo::Api` (DECISIONS D-SKEL-004).
require "../lib/partiduo-ui-bulma/spec/support/accounts"
require "../lib/partiduo-ui-bulma/spec/support/browser"
require "../lib/partiduo-ui-bulma/spec/support/reference"
require "../lib/partiduo-ui-bulma/spec/support/books"

require "./support/**"
