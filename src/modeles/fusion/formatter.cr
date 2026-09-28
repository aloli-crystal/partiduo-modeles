# SPDX-License-Identifier: AGPL-3.0-or-later

module Modeles
  module Fusion
    # Présentation des montants, quantités, taux et dates dans la langue du
    # document (ADR-010 D2), avec les conventions du PDF légal de la
    # Facturation : `1 234,56` (fr), `1,234.56` (en), `1.234,56` (nl) ;
    # dates `15/09/2026` (fr), `2026-09-15` (en), `15-09-2026` (nl).
    struct Formatter
      getter locale : String

      def initialize(@locale : String)
      end

      # Montant à deux décimales, groupé par milliers.
      def amount(value : BigDecimal) : String
        integer, fraction = Formatter.fixed(value, 2)
        negative = integer.starts_with?('-')
        digits = integer.lchop('-')
        grouped = digits.reverse.scan(/\d{1,3}/).map(&.[0]).join(thousands).reverse
        "#{negative ? "-" : ""}#{grouped}#{decimal}#{fraction}"
      end

      # Quantité sans zéros inutiles (`10`, `2,5`).
      def quantity(value : BigDecimal) : String
        text = Formatter.plain(value)
        locale == "en" ? text : text.tr(".", ",")
      end

      # Taux en pour cent : `20 %` (fr), `20%` (en, nl).
      def percent(value : BigDecimal) : String
        locale == "fr" ? "#{quantity(value)} %" : "#{quantity(value)}%"
      end

      def date(value : Time?) : String
        return "" unless value
        case locale
        when "en" then value.to_s("%Y-%m-%d")
        when "nl" then value.to_s("%d-%m-%Y")
        else           value.to_s("%d/%m/%Y")
        end
      end

      private def thousands : String
        case locale
        when "en" then ","
        when "nl" then "."
        else           " "
        end
      end

      private def decimal : String
        locale == "en" ? "." : ","
      end

      # Partie entière et partie décimale sur `places` chiffres, arrondi
      # commercial (demi à l'écart de zéro).
      def self.fixed(value : BigDecimal, places : Int32) : {String, String}
        rounded = value.round(places, mode: :ties_away)
        integer, _, fraction = plain(rounded).partition('.')
        integer = "0" if integer.empty? || integer == "-"
        {integer, fraction.ljust(places, '0')[0, places]}
      end

      # Écriture décimale sans exposant ni zéro final (`12.50` → `12.5`).
      def self.plain(value : BigDecimal) : String
        text = value.to_s
        text = text.rstrip('0').rchop('.') if text.includes?('.')
        text == "-0" ? "0" : text
      end
    end
  end
end
