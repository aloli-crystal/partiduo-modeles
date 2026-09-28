# SPDX-License-Identifier: AGPL-3.0-or-later

# Instance de démonstration de l'extension MODELES, à ouvrir dans un
# navigateur : cœur, interface Bulma et extension composés comme dans une
# distribution (modèle : `partiduo-skel/scripts/server.cr`).
#
# À chaque lancement, la base de démonstration est *vidée* puis
# reconstruite par les migrations ; le script y crée :
#
# * un dossier français (Atelier Brunet SARL), la Facturation paramétrée
#   (IBAN, BIC) et l'extension MODELES active ;
# * l'administrateur `demo@partiduo.test`, mot de passe `Gabarit-Fusion-2026`
#   (identifiants de démonstration, jamais ceux d'une vraie instance) ;
# * une facture et un devis émis, un avoir, une facture en brouillon ;
# * les modèles de départ en français (facture, devis, avoir × AsciiDoc,
#   Markdown, ODT, DOCX) et la facture en anglais et en néerlandais (ODT),
#   actifs, l'ODT par défaut ; un premier rendu conservé de la facture.
#
# ```
# createdb -h /tmp partiduo_demo_modeles
# crystal run scripts/demo.cr -- [--port=8000] [--host=127.0.0.1] [--converters=auto]
# ```
#
# `DATABASE_URL` (défaut `postgres:///partiduo_demo_modeles?host=/tmp`) doit
# désigner une base dont le nom contient « demo ». `--converters=auto`
# cherche `soffice`, `asciidoctor-pdf` et `pandoc` dans le `PATH` (sinon :
# variables `PARTIDUO_MODELES_*` de l'instance, voir le README). Ctrl-C
# arrête le serveur, comme la création du fichier `--stop-file` (défaut :
# `partiduo-modeles-demo.stop` dans le dossier temporaire), utile quand le
# serveur tourne sans terminal.
require "option_parser"

ENV["MARTEN_ENV"] ||= "development"
ENV["DATABASE_URL"] ||= "postgres:///partiduo_demo_modeles?host=/tmp"
ENV["PARTIDUO_MODULES"] ||= "invoicing"
ENV["PARTIDUO_MEDIA_ROOT"] ||= File.join(Dir.tempdir, "partiduo-modeles-demo-media")

require "partiduo-ui-bulma/partiduo_ui"
require "../src/partiduo-modeles"
require "../ui/bulma/bulma"
require "../config/settings/base"
require "../config/settings/**"
require "partiduo/cli"
require "../src/partiduo-modeles/cli"

module ModelesDemo
  alias Api = Modeles::Api
  alias Inv = Partiduo::Api::Invoicing
  alias Cards = Partiduo::Api::Cards

  EMAIL    = "demo@partiduo.test"
  PASSWORD = "Gabarit-Fusion-2026"
  SYSTEM   = Partiduo::Api::Actor.system

  def self.d(text : String) : BigDecimal
    BigDecimal.new(text)
  end

  # Schéma reconstruit par les migrations (cœur et extension).
  def self.reset! : Nil
    connection = Marten::DB::Connection.default
    name = Marten.settings.databases.first.name.to_s
    abort "Base refusée : « #{name} » ne contient pas « demo » (voir DATABASE_URL)." unless name.includes?("demo")
    connection.open do |db|
      db.exec("DROP SCHEMA public CASCADE")
      db.exec("CREATE SCHEMA public")
    end
    Marten::DB::Management::Migrations::Runner.new(connection).execute
    Partiduo::Modules::State.reset_table_cache
  end

  def self.seed : String
    settings = Partiduo::Api::Core::SettingsInput.new(company_name: "Atelier Brunet SARL", tax_regime: "fr",
      country_code: "FR", siren: "732 829 320", vat_number: "FR 44 732829320", domain: "demo.partiduo.localhost")
    Partiduo::Api::Core.provision(SYSTEM, Partiduo::Api::Core::ProvisionInput.new(settings: settings)).value!
    profile = Partiduo::Api::Auth.ensure_default_profiles(SYSTEM).find! { |item| item.code == "ADMIN" }.id
    user = Partiduo::Api::Auth.create_user(SYSTEM, Partiduo::Api::Auth::UserInput.new(
      email: EMAIL, first_name: "Camille", last_name: "Démo", role: "member", profile_id: profile, password: PASSWORD)).value!
    Partiduo::Api::Modules.activate(SYSTEM, Modeles::CODE).value!
    current = Inv.settings(SYSTEM)
    Inv.update_settings(SYSTEM, current.to_input.copy_with(iban: "FR7630006000011234567890189", bic: "AGRIFRPP")).value!
    admin = Partiduo::Api::Actor.user(user.user.id, [Api::READ, Api::ADMIN, "invoicing.invoice.read"], level: 3)

    customer = Cards.create_card(SYSTEM, Cards::CardInput.new(
      category_id: category("CUSTOMER"), name: "Durand & Fils", siren: "552100554", customer_nature: "business",
      email: "compta@durand.test", address: Cards::AddressInput.new(line1: "3 rue du Port", line2: "Bâtiment B",
      postcode: "13002", city: "Marseille", country_code: "FR"))).value!
    rate = Partiduo::Api::Vat.rate_by_code(SYSTEM, "NOR") || abort "taux de TVA normal absent"
    item = Cards.create_card(SYSTEM, Cards::CardInput.new(category_id: category("SALE"), name: "Conseil", code: "CONSEIL",
      unit_code: "HUR", sale_price: d("80"), vat_rate_id: rate.id)).value!
    lines = [
      Inv::LineInput.new(kind: "title", description: "Mission d'audit"),
      Inv::LineInput.new(item_card_id: item.id, quantity: d("10"), description: "Conseil en organisation\nsur site"),
      Inv::LineInput.new(item_card_id: item.id, quantity: d("2.5"), discount_kind: "percent", discount_value: d("10")),
    ]
    today = Partiduo::Api::Core.today
    document = ->(kind : String, credited : Int64?) do
      Inv.create_document(SYSTEM, Inv::DocumentInput.new(kind: kind, customer_card_id: customer.id, lines: lines,
        buyer_reference: "BC-42", order_reference: "CMD-17", credited_document_id: credited)).value!
    end
    invoice = Inv.issue(SYSTEM, document.call("invoice", nil).id, Inv::IssueInput.new(today)).value!
    Inv.issue(SYSTEM, document.call("quote", nil).id, Inv::IssueInput.new(today)).value!
    Inv.issue(SYSTEM, document.call("credit_note", invoice.id).id, Inv::IssueInput.new(today)).value!
    document.call("invoice", nil)

    starters = Modeles::Config::KINDS.flat_map { |kind| Modeles::Config::FORMATS.map { |format| {kind, "fr", format} } }
    starters += [{"invoice", "en", "odt"}, {"invoice", "nl", "odt"}]
    starters.each do |(kind, locale, format)|
      name = "#{I18n.with_locale(locale) { I18n.t("modeles.kinds.#{kind}") }} — #{I18n.t("modeles.formats.#{format}")}"
      view = Api.upload(admin, Api::UploadInput.new(filename: Modeles::Starters.filename(kind, locale, format),
        content: Modeles::Starters.file(kind, locale, format), name: name, kind: kind, locale: locale)).value!
      Api.activate(admin, view.id).value!
      Api.set_default(admin, view.id).value! if format == "odt"
    end
    Api.render(admin, invoice.id, pdf: true).value!
    invoice.number.to_s
  end

  def self.category(code : String) : Int64
    (Cards.category_by_code(SYSTEM, code) || abort "catégorie #{code} absente").id
  end
end

host = "127.0.0.1"
port = (ENV["PORT"]? || "8000").to_i
stop_file = File.join(Dir.tempdir, "partiduo-modeles-demo.stop")
OptionParser.parse do |parser|
  parser.banner = "Usage : crystal run scripts/demo.cr -- [--port=8000] [--host=127.0.0.1] [--converters=auto]"
  parser.on("--port=PORT", "port local du serveur") { |value| port = value.to_i }
  parser.on("--host=HOST", "adresse d'écoute") { |value| host = value }
  parser.on("--stop-file=PATH", "fichier dont la création arrête le serveur") { |value| stop_file = value }
  parser.on("--converters=MODE", "auto : convertisseurs PDF cherchés dans le PATH") do |value|
    if value == "auto"
      %w[PARTIDUO_MODELES_SOFFICE PARTIDUO_MODELES_ASCIIDOCTOR_PDF PARTIDUO_MODELES_PANDOC].each { |name| ENV[name] ||= "auto" }
    end
  end
end

Marten.configure(&.log_level=(::Log::Severity::Warn))
Marten.setup
ModelesDemo.reset!
number = ModelesDemo.seed
Marten.settings.host = host
Marten.settings.port = port
Marten::Server.setup
puts <<-TEXT
  == Instance de démonstration MODELES : http://#{host}:#{port}/
     Connexion : #{ModelesDemo::EMAIL} / #{ModelesDemo::PASSWORD}
     Modèles : http://#{host}:#{port}/ext/MODELES/ · facture émise #{number} : « Rendre un document »
     Convertisseurs PDF : #{Modeles::Config::FORMATS.map { |format| "#{format} #{Modeles::Converters.available?(format) ? "oui" : "non"}" }.join(", ")}
     Ctrl-C ou `touch #{stop_file}` pour arrêter.
  TEXT
File.delete?(stop_file)
spawn do
  until File.exists?(stop_file)
    sleep 1.second
  end
  File.delete?(stop_file)
  puts "== Arrêt demandé (#{stop_file})."
  Marten::Server.stop
  exit 0
end
Marten::Server.start
