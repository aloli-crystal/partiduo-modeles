# SPDX-License-Identifier: AGPL-3.0-or-later

require "../spec_helper"

private alias S = Modeles::SpecSupport
private alias Api = Modeles::Api

private def admin : PartiduoUi::Browser
  S.books
  PartiduoUi::Accounts.signed_in
end

describe "Écrans de l'extension sous /ext/MODELES/ (ADR-010, ADR-005 D4)" do
  it "est montée sous le code de l'extension, lecture pour tous, administration à part" do
    Marten.routes.reverse("modeles:index").should eq("/ext/MODELES/")
    mount = PartiduoUi::Extensions["MODELES"]? || raise("interface non montée")
    mount.permission.should eq(Api::READ)
    mount.permission_for("modeles:upload").should eq(Api::ADMIN)
    mount.permission_for("modeles:render").should eq(Api::READ)
  end

  it "n'existe pas tant que l'extension est inactive (404)" do
    S.books(activate: false)
    PartiduoUi::Accounts.signed_in.get("/ext/MODELES/").status.should eq(404)
  end

  it "liste les modèles, les modèles de départ, les convertisseurs et le vocabulaire" do
    browser = admin
    S.template
    html = browser.get("/ext/MODELES/").html
    html.should contain("Modèles de documents")
    html.should contain("data-modeles-template=")
    html.should contain("En service")
    html.should contain("data-modeles-default")
    html.should contain(%(href="/ext/MODELES/starters/invoice/fr/odt"))
    html.should contain(%(data-modeles-converter="missing"))
    html.should contain("PARTIDUO_MODELES_SOFFICE")
    html.should contain("{{ facture.numero }}")
    html.should contain(%(enctype="multipart/form-data"))
    html.should contain("modeles/css/modeles.css")
  end

  it "télécharge un modèle de départ" do
    browser = admin
    response = browser.get("/ext/MODELES/starters/quote/nl/docx")
    response.status.should eq(200)
    response.content_type.should start_with(Modeles::Config::CONTENT_TYPES["docx"])
    response.headers["Content-Disposition"].should eq(%(attachment; filename="modele-devis-nl.docx"))
    response.content.to_slice.should eq(Modeles::Starters.file("quote", "nl", "docx"))
    browser.get("/ext/MODELES/starters/order/fr/odt").status.should eq(404)
  end

  it "dépose un modèle : refus motivé avec le rapport, puis dépôt, aperçu, activation, défaut" do
    browser = admin
    refused = S.upload(browser, "/ext/MODELES/upload", {"name" => "Maison", "kind" => "invoice", "locale" => "fr"},
      {"file", "maison.md", "# {{ facture.numero }}".to_slice})
    refused.status.should eq(422)
    html = refused.html
    html.should contain("data-modeles-report")
    html.should contain("Mention obligatoire absente : les mentions légales")
    html.should contain(%(value="Maison"))

    missing = S.upload(browser, "/ext/MODELES/upload", {"name" => "Maison", "kind" => "invoice", "locale" => "fr"}, nil)
    missing.status.should eq(422)
    missing.html.should contain("Choisissez le fichier du modèle.")

    saved = S.upload(browser, "/ext/MODELES/upload", {"name" => "Maison", "kind" => "invoice", "locale" => "fr"},
      {"file", "maison.odt", Modeles::Starters.file("invoice", "fr", "odt")})
    saved.status.should eq(302)
    page = browser.follow(saved).html
    page.should contain("Modèle contrôlé et déposé (version 1)")
    page.should contain("data-modeles-pending")
    page.should contain("data-modeles-no-pdf")
    id = Api.templates(S.actor).first.id

    preview = browser.get("/ext/MODELES/templates/#{id}/versions/1/preview")
    preview.status.should eq(200)
    preview.headers["Content-Disposition"].should eq(%(attachment; filename="apercu-maison-v1.odt"))
    no_pdf = browser.get("/ext/MODELES/templates/#{id}/versions/1/preview?pdf=1")
    browser.follow(no_pdf).html.should contain("Pas de convertisseur PDF pour ce format sur ce serveur.")

    activated = browser.post("/ext/MODELES/templates/#{id}/activate", {"version" => "1"})
    browser.follow(activated).html.should contain("Version mise en service.")
    default = browser.post("/ext/MODELES/templates/#{id}/default")
    browser.follow(default).html.should contain("Modèle désigné par défaut pour son type et sa langue.")
    Api.template(S.actor, id).is_default.should be_true

    version = S.upload(browser, "/ext/MODELES/upload", {"template_id" => id.to_s},
      {"file", "maison.odt", S::OfficeFiles.odt(S::OfficeFiles.tp("{{ facture.numero }}"))})
    version.status.should eq(422)
    version.html.should contain("Déposer une nouvelle version")
    version.html.should contain("data-modeles-report")

    retired = browser.post("/ext/MODELES/templates/#{id}/retire")
    browser.follow(retired).html.should contain("Modèle retiré.")
  end

  it "montre l'aperçu PDF quand le convertisseur est déclaré" do
    browser = admin
    view = S.template(format: "asciidoc")
    S.fake_converters
    response = browser.get("/ext/MODELES/templates/#{view.id}/versions/1/preview?pdf=1")
    response.status.should eq(200)
    response.content_type.should start_with("application/pdf")
    response.headers["Content-Disposition"].should start_with("inline;")
  end

  it "rend une facture émise depuis sa page, la conserve et la propose au téléchargement" do
    browser = admin
    S.template(format: "docx")
    S.fake_converters
    invoice = S.issue
    list = browser.get("/ext/MODELES/documents?q=#{invoice.number}").html
    list.should contain(%(data-modeles-document="#{invoice.id}"))
    page = browser.get("/ext/MODELES/documents/#{invoice.id}").html
    page.should contain("Rendre avec un modèle")
    page.should contain(%(href="/invoicing/documents/#{invoice.id}"))
    page.should contain("Rendre et conserver")
    rendered = browser.post("/ext/MODELES/documents/#{invoice.id}/render", {"template_id" => Api.templates(S.actor).first.id.to_s,
                                                                            "pdf"         => "1"})
    rendered.status.should eq(302)
    html = browser.follow(rendered).html
    html.should contain("Document rendu et conservé")
    html.should contain(%(aria-current="true"))
    rendition = Api.renditions(S.actor, invoice.id).first
    file = browser.get("/ext/MODELES/renditions/#{rendition.id}/file")
    file.status.should eq(200)
    file.content.to_slice.should eq(Api.rendition_file(S.actor, rendition.id).content)
    browser.get("/ext/MODELES/renditions/#{rendition.id}/pdf").content_type.should start_with("application/pdf")
    browser.get("/ext/MODELES/renditions/#{rendition.id}/autre").status.should eq(404)
    browser.get("/ext/MODELES/renditions").html.should contain(invoice.number.to_s)
  end

  it "ajoute à la fiche du document son panneau : « Rendre avec un modèle » et rendus conservés" do
    browser = admin
    S.template(format: "odt")
    S.fake_converters
    invoice = S.issue
    html = browser.get("/invoicing/documents/#{invoice.id}").html
    panel = html.match(/<aside class="pd-panel pd-ext-panel"[^>]*data-extension="MODELES".*?<\/aside>/m).try(&.[0]) || fail "panneau absent"
    panel.should contain(%(<h2 id="pd-ext-modeles-title">Modèles de documents</h2>))
    panel.should contain(%(<a class="button pd-touch" href="/ext/MODELES/documents/#{invoice.id}">))
    panel.should contain("Rendre avec un modèle")
    panel.should_not contain("pd-ext-files")

    browser.post("/ext/MODELES/documents/#{invoice.id}/render", {"template_id" => Api.templates(S.actor).first.id.to_s, "pdf" => "1"})
    rendition = Api.renditions(S.actor, invoice.id).first
    panel = browser.get("/invoicing/documents/#{invoice.id}").html.match(/<aside class="pd-panel pd-ext-panel"[^>]*data-extension="MODELES".*?<\/aside>/m).try(&.[0]) || fail "panneau absent"
    panel.should contain(%(href="/ext/MODELES/renditions/#{rendition.id}/file"))
    panel.should contain(rendition.filename)
    panel.should contain(%(href="/ext/MODELES/renditions/#{rendition.id}/pdf"))
    panel.should contain(rendition.pdf_filename.to_s)
    # L'écran propre n'est plus annoncé par la page de l'extension.
    browser.get("/ext/MODELES/").html.should_not contain(%(href="/ext/MODELES/documents"))
  end

  it "n'ajoute pas de panneau sans modeles.read ni quand l'extension est inactive" do
    S.books
    invoice = S.issue
    reader = S.signed_in_with(["invoicing.invoice.read"], "vendeur@example.com")
    page = reader.get("/invoicing/documents/#{invoice.id}")
    page.status.should eq(200)
    page.html.should_not contain(%(data-extension="MODELES"))
    Partiduo::Api::Modules.deactivate(S::SYSTEM, Modeles::CODE).success?.should be_true
    PartiduoUi::Accounts.signed_in.get("/invoicing/documents/#{invoice.id}").html.should_not contain(%(data-extension="MODELES"))
  end

  it "rend un brouillon en aperçu téléchargé aussitôt, sans le conserver" do
    browser = admin
    S.template
    draft = S.draft
    browser.get("/ext/MODELES/documents/#{draft.id}").html.should contain("data-modeles-draft")
    response = browser.post("/ext/MODELES/documents/#{draft.id}/render", {"pdf" => "1"})
    response.status.should eq(200)
    response.headers["Content-Disposition"].should eq(%(attachment; filename="brouillon-#{draft.id}.md"))
    response.content.should start_with("**Brouillon — sans valeur**")
    Api.renditions(S.actor).should be_empty
  end

  it "signale un document sans modèle actif" do
    browser = admin
    invoice = S.issue
    browser.get("/ext/MODELES/documents/#{invoice.id}").html.should contain("data-modeles-no-template")
    failed = browser.post("/ext/MODELES/documents/#{invoice.id}/render", {"template_id" => ""})
    browser.follow(failed).html.should contain("Aucun modèle par défaut pour ce type de document")
  end

  it "interdit le dépôt à qui n'a que modeles.read (403) mais lui permet de rendre" do
    S.books
    S.template
    invoice = S.issue
    browser = S.signed_in_with([Api::READ, "invoicing.invoice.read"])
    html = browser.get("/ext/MODELES/").html
    html.should_not contain("data-modeles-upload")
    S.upload(browser, "/ext/MODELES/upload", {"name" => "x", "kind" => "invoice", "locale" => "fr"},
      {"file", "x.md", Modeles::Starters.file("invoice", "fr", "markdown")}).status.should eq(403)
    browser.post("/ext/MODELES/templates/#{Api.templates(S.actor).first.id}/retire").status.should eq(403)
    browser.post("/ext/MODELES/documents/#{invoice.id}/render").status.should eq(302)
    Api.renditions(S.actor).size.should eq(1)
  end

  it "refuse l'extension à qui n'a pas modeles.read (403)" do
    S.books
    browser = S.signed_in_with(["invoicing.invoice.read"], "vendeur@example.com")
    browser.get("/ext/MODELES/").status.should eq(403)
  end

  it "affiche les écrans en anglais et en néerlandais" do
    S.books
    S.template
    en = PartiduoUi::Browser.new("en")
    en.jar[Marten.settings.i18n.locale_cookie_name] = "en"
    en.post("/login", {"email" => "alice@example.com", "password" => PartiduoUi::Accounts::PASSWORD})
    en.get("/ext/MODELES/").html.should contain("Starter templates")
    nl = PartiduoUi::Browser.new("nl")
    nl.jar[Marten.settings.i18n.locale_cookie_name] = "nl"
    nl.post("/login", {"email" => "alice@example.com", "password" => PartiduoUi::Accounts::PASSWORD})
    nl.get("/ext/MODELES/").html.should contain("Startsjablonen")
  end
end
