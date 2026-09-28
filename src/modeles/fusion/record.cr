# SPDX-License-Identifier: AGPL-3.0-or-later

module Modeles
  module Fusion
    # Objet du contexte de fusion (`facture`, `vendeur`, une ligne…), lu par
    # le moteur de gabarits de Marten par ses seuls champs : aucun accès à un
    # modèle de données ni à une méthode (ADR-010 D2). Les valeurs sont déjà
    # présentées et échappées selon le format (`Escaper`). Objet plutôt que
    # `Hash` : Marten ne retrouve pas les clés d'un grand `Hash` (BLOCAGES
    # B-EINV-001 du cœur).
    class Record
      include Marten::Template::Object

      alias Value = (String | Bool | Record | Array(Record) | Block)?

      getter values : Hash(String, Value)

      def initialize(@values : Hash(String, Value) = {} of String => Value)
      end

      def []=(key : String, value : Value) : Value
        @values[key] = value
      end

      def []?(key : String) : Value
        @values[key]?
      end

      def resolve_template_attribute(key : String)
        @values[key]?
      end

      # Un objet imprimé tel quel ne produit rien (le contrôle au dépôt le
      # refuse : « champ incomplet »).
      def to_s(io : IO) : Nil
      end
    end

    # Bloc imprimable et parcourable : `{{ mentions }}` imprime toutes les
    # mentions légales, une par ligne ; `{% for mention in mentions %}` les
    # parcourt (`mention.code`, `mention.texte`).
    class Block
      include Marten::Template::Object
      include Enumerable(Marten::Template::Value)

      getter items : Array(Record)

      # `text` : le bloc déjà échappé, lignes séparées selon le format.
      def initialize(@items : Array(Record), @text : String)
      end

      def each(& : Marten::Template::Value ->) : Nil
        @items.each { |item| yield Marten::Template::Value.from(item) }
      end

      def empty? : Bool
        @items.empty?
      end

      def resolve_template_attribute(key : String)
        nil
      end

      def to_s(io : IO) : Nil
        io << @text
      end
    end
  end
end
