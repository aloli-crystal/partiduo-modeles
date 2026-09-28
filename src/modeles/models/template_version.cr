# SPDX-License-Identifier: AGPL-3.0-or-later

module Modeles
  # Version d'un modèle (ADR-010 D3) : chaque dépôt en crée une, numérotée à
  # partir de 1 ; les documents déjà rendus gardent la leur. `warnings` :
  # remarques non bloquantes du contrôle, en JSON (`[{"key": …, "params":
  # {…}}]`).
  class TemplateVersion < Marten::Model
    field :id, :big_int, primary_key: true, auto: true
    field :template_id, :big_int, index: true
    field :number, :int
    field :file_id, :big_int
    field :filename, :string, max_size: 255
    field :byte_size, :big_int
    field :sha256, :string, max_size: 64
    field :warnings, :text, blank: true, default: "[]"
    field :uploaded_by_id, :big_int, blank: true, null: true

    with_timestamp_fields
  end
end
