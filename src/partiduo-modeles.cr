# SPDX-License-Identifier: AGPL-3.0-or-later

# Point d'entrée du shard `partiduo-modeles` : le métier de l'extension
# MODELES (manifeste, modèles de données, moteur de fusion, contrat
# `Modeles::Api`), sans interface. L'interface Bulma est dans `ui/bulma/`,
# requise à part par la distribution : `require "partiduo-modeles/ui/bulma"`.
#
# La distribution ajoute ensuite `Modeles::INSTALLED_APPS` à ses
# applications Marten, et `require "partiduo-modeles/cli"` à sa ligne de
# commande (migrations).
require "partiduo"

require "./modeles/app"
