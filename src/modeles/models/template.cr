# SPDX-License-Identifier: AGPL-3.0-or-later

module Modeles
  # Modèle de document déposé (ADR-010 D3) : nom, type de document
  # (`invoice`, `quote`, `credit_note`), langue et format. Ses fichiers sont
  # des versions (`TemplateVersion`) ; `active_version` est le numéro de la
  # version en service (`nil` : pas encore activé). Un modèle retiré
  # (`retired_at`) ne sert plus mais garde ses versions et ses rendus.
  # Interne : on le lit et on l'écrit par `Modeles::Api`.
  class Template < Marten::Model
    field :id, :big_int, primary_key: true, auto: true
    field :name, :string, max_size: 120
    field :kind, :string, max_size: 16
    field :locale, :string, max_size: 2
    field :format, :string, max_size: 16
    field :active_version, :int, blank: true, null: true
    # Modèle par défaut pour son type et sa langue (un seul, index partiel
    # unique posé par la migration ; seulement un modèle actif).
    field :is_default, :bool, default: false
    field :retired_at, :date_time, blank: true, null: true
    field :created_by_id, :big_int, blank: true, null: true

    with_timestamp_fields
  end
end
