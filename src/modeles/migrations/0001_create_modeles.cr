# SPDX-License-Identifier: AGPL-3.0-or-later

# Modèles de documents multiformats (ADR-010) : fichiers, modèles, versions
# et rendus conservés.
#
# Intégrité en base :
#
# * type de document, langue et format contrôlés ;
# * un fichier est soit une pièce jointe du socle, soit un fichier du
#   stockage de l'instance (BLOCAGE B-MOD-001) ;
# * un seul modèle par défaut par type de document et langue, actif et non
#   retiré ;
# * numéros de version uniques par modèle ;
# * les pièces jointes citées ne peuvent plus être effacées du socle
#   (ADR-003 D5), ni les fichiers, versions et modèles cités par un rendu.
class Migration::Modeles::V0001 < Marten::Migration
  depends_on :core, "0002_core_referential"

  KINDS   = "('invoice', 'quote', 'credit_note')"
  LOCALES = "('fr', 'en', 'nl')"
  FORMATS = "('asciidoc', 'markdown', 'odt', 'docx')"

  CONSTRAINTS = [
    <<-SQL,
      ALTER TABLE modeles_stored_file
        ADD CONSTRAINT modeles_stored_file_storage_check CHECK ((attachment_id IS NULL) <> (storage_name IS NULL)),
        ADD CONSTRAINT modeles_stored_file_attachment_fk FOREIGN KEY (attachment_id) REFERENCES core_attachment (id)
      SQL
    <<-SQL,
      ALTER TABLE modeles_template
        ADD CONSTRAINT modeles_template_kind_check CHECK (kind IN #{KINDS}),
        ADD CONSTRAINT modeles_template_locale_check CHECK (locale IN #{LOCALES}),
        ADD CONSTRAINT modeles_template_format_check CHECK (format IN #{FORMATS}),
        ADD CONSTRAINT modeles_template_default_check
          CHECK (NOT is_default OR (active_version IS NOT NULL AND retired_at IS NULL))
      SQL
    "CREATE UNIQUE INDEX modeles_template_default_uniq ON modeles_template (kind, locale) WHERE is_default",
    <<-SQL,
      ALTER TABLE modeles_template_version
        ADD CONSTRAINT modeles_template_version_template_fk FOREIGN KEY (template_id) REFERENCES modeles_template (id),
        ADD CONSTRAINT modeles_template_version_file_fk FOREIGN KEY (file_id) REFERENCES modeles_stored_file (id),
        ADD CONSTRAINT modeles_template_version_number_check CHECK (number >= 1),
        ADD CONSTRAINT modeles_template_version_number_uniq UNIQUE (template_id, number)
      SQL
    <<-SQL,
      ALTER TABLE modeles_rendition
        ADD CONSTRAINT modeles_rendition_format_check CHECK (format IN #{FORMATS}),
        ADD CONSTRAINT modeles_rendition_locale_check CHECK (locale IN #{LOCALES}),
        ADD CONSTRAINT modeles_rendition_template_fk FOREIGN KEY (template_id) REFERENCES modeles_template (id),
        ADD CONSTRAINT modeles_rendition_version_fk FOREIGN KEY (version_id) REFERENCES modeles_template_version (id),
        ADD CONSTRAINT modeles_rendition_file_fk FOREIGN KEY (file_id) REFERENCES modeles_stored_file (id),
        ADD CONSTRAINT modeles_rendition_pdf_file_fk FOREIGN KEY (pdf_file_id) REFERENCES modeles_stored_file (id),
        ADD CONSTRAINT modeles_rendition_pdf_check CHECK ((pdf_file_id IS NULL) = (pdf_sha256 IS NULL))
      SQL
  ]

  def plan
    create_table :modeles_stored_file do
      column :id, :big_int, primary_key: true, auto: true
      column :attachment_id, :big_int, null: true
      column :storage_name, :string, max_size: 255, null: true
      column :filename, :string, max_size: 255
      column :content_type, :string, max_size: 128
      column :byte_size, :big_int
      column :sha256, :string, max_size: 64
      column :created_at, :date_time
      column :updated_at, :date_time
    end

    create_table :modeles_template do
      column :id, :big_int, primary_key: true, auto: true
      column :name, :string, max_size: 120
      column :kind, :string, max_size: 16
      column :locale, :string, max_size: 2
      column :format, :string, max_size: 16
      column :active_version, :int, null: true
      column :is_default, :bool, default: false
      column :retired_at, :date_time, null: true
      column :created_by_id, :big_int, null: true
      column :created_at, :date_time
      column :updated_at, :date_time
    end

    create_table :modeles_template_version do
      column :id, :big_int, primary_key: true, auto: true
      column :template_id, :big_int, index: true
      column :number, :int
      column :file_id, :big_int
      column :filename, :string, max_size: 255
      column :byte_size, :big_int
      column :sha256, :string, max_size: 64
      column :warnings, :text, default: "[]"
      column :uploaded_by_id, :big_int, null: true
      column :created_at, :date_time
      column :updated_at, :date_time
    end

    create_table :modeles_rendition do
      column :id, :big_int, primary_key: true, auto: true
      column :document_id, :big_int, index: true
      column :document_kind, :string, max_size: 32
      column :document_number, :string, max_size: 64
      column :locale, :string, max_size: 2
      column :template_id, :big_int, index: true
      column :version_id, :big_int
      column :version_number, :int
      column :format, :string, max_size: 16
      column :file_id, :big_int
      column :sha256, :string, max_size: 64
      column :pdf_file_id, :big_int, null: true
      column :pdf_sha256, :string, max_size: 64, null: true
      column :pdf_error, :string, max_size: 128, default: ""
      column :rendered_by_id, :big_int, null: true
      column :created_at, :date_time
      column :updated_at, :date_time
    end

    CONSTRAINTS.each { |sql| execute(sql, "SELECT 1") }
  end
end
