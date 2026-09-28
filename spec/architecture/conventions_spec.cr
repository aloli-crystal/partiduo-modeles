# SPDX-License-Identifier: AGPL-3.0-or-later

require "../spec_helper"
require "../../lib/partiduo-ui-bulma/scripts/api_boundary"

private def source_files(pattern : String) : Array(String)
  Dir.glob(File.join(Modeles::SpecSupport::ROOT, pattern)).reject(&.includes?("/lib/")).sort!
end

private def flatten_keys(value : YAML::Any, prefix : String = "") : Array(String)
  if hash = value.as_h?
    hash.flat_map { |key, child| flatten_keys(child, prefix.empty? ? key.as_s : "#{prefix}.#{key.as_s}") }
  else
    [prefix]
  end
end

describe "Conventions de l'extension MODELES" do
  it "ouvre chaque fichier source par l'en-tête SPDX" do
    missing = (source_files("{src,ui,spec,config,scripts}/**/*.cr") + source_files("*.cr")).reject do |path|
      File.read_lines(path).first? == "# SPDX-License-Identifier: AGPL-3.0-or-later"
    end
    missing += source_files("ui/**/*.html").reject do |path|
      File.read(path).starts_with?("{# SPDX-License-Identifier: AGPL-3.0-or-later")
    end
    missing += source_files("{ui/**/*.{js,css},spec/support/bin/*,scripts/*.sh}").reject do |path|
      File.read(path).includes?("SPDX-License-Identifier: AGPL-3.0-or-later")
    end
    missing.should be_empty
  end

  it "ne cite le logiciel d'origine que dans la documentation (*.adoc, *.md)" do
    root = Modeles::SpecSupport::ROOT
    name = "noa" + "lyss"
    output = IO::Memory.new
    status = Process.run("git", ["-C", root, "grep", "-il", name, "--", ".", ":!*.adoc", ":!*.md"], output: output)
    # git grep rend 1 quand rien n'est trouvé, 0 sinon ; tout autre code est une erreur.
    status.exit_code.should_not eq(128)
    output.to_s.lines.should eq([] of String)
    source_files("**/*").select { |path| File.basename(path).downcase.includes?(name) }.should be_empty
  end

  it "a les mêmes clés de traduction en fr, en et nl" do
    %w[src/modeles/locales ui/bulma/locales].each do |dir|
      keys = Partiduo::LOCALES.to_h do |locale|
        tree = YAML.parse(File.read(File.join(Modeles::SpecSupport::ROOT, dir, "#{locale}.yml")))
        {locale, flatten_keys(tree[locale]).sort}
      end
      keys["en"].should eq(keys["fr"])
      keys["nl"].should eq(keys["fr"])
    end
  end

  it "traduit toute clé citée par le code et les gabarits de l'extension" do
    cited = source_files("{src,ui}/**/*.{cr,html}").flat_map do |path|
      File.read(path).scan(/["'](modeles(?:_ui)?\.[a-z_]+(?:\.[a-z0-9_]+)+)["']/).map(&.[1])
    end.uniq! - Partiduo::Modules[Modeles::CODE].permissions
    cited.size.should be > 40
    missing = Partiduo::LOCALES.flat_map do |locale|
      I18n.with_locale(locale) do
        cited.select { |key| I18n.t(key).includes?("missing translation") && I18n.t("#{key}.one").includes?("missing translation") }
          .map { |key| "#{locale}:#{key}" }
      end
    end
    missing.should be_empty
  end

  it "traduit chaque code de contrôle, exigence et champ du vocabulaire" do
    codes = source_files("src/**/*.cr").flat_map do |path|
      File.read(path).scan(/(?:error|warning|issue|Issue\.new)\("([a-z_]+)"/).map(&.[1])
    end.uniq!
    codes.size.should be > 15
    requirements = (Modeles::Fusion::Requirements::COMMON + Modeles::Fusion::Requirements::BY_KIND.values.flatten).map(&.code)
    fields = Modeles::Fusion::Vocabulary.paths
    Partiduo::LOCALES.each do |locale|
      I18n.with_locale(locale) do
        codes.select { |code| I18n.t("modeles.check.#{code}").includes?("missing translation") }.should eq([] of String)
        requirements.select { |code| I18n.t("modeles.requirements.#{code}").includes?("missing translation") }.should be_empty
        fields.select { |path| I18n.t("modeles.vocabulary.#{path}").includes?("missing translation") }.should be_empty
        Modeles::Fusion::Vocabulary::OBJECTS.keys.each { |group| I18n.t("modeles.vocabulary.groups.#{group}").should_not contain("missing translation") }
      end
    end
  end

  it "range ses tables sous le préfixe modeles_ (ADR-003 D5)" do
    [Modeles::Template, Modeles::TemplateVersion, Modeles::StoredFile, Modeles::Rendition].map(&.db_table).should eq(
      %w[modeles_template modeles_template_version modeles_stored_file modeles_rendition])
  end

  it "ne parle au cœur, depuis ui/bulma, que par Partiduo::Api (ADR-005 D3)" do
    root = Modeles::SpecSupport::ROOT
    ApiBoundary.scan([File.join(root, "ui")], base: root).map(&.to_s).should eq([] of String)
  end

  it "ne parle au métier de l'extension, depuis ui/bulma, que par Modeles::Api (ADR-005 D4)" do
    allowed = %w[Api Ui CODE VERSION]
    internals = %w[Config Converters Fusion Office Starters Templates Files Sample Template TemplateVersion StoredFile Rendition]
    leaks = source_files("ui/**/*.cr").flat_map do |path|
      File.read_lines(path).each_with_index(1).flat_map do |line, number|
        code = ApiBoundary.strip_comment(line)
        qualified = code.scan(/(?<![\w:])Modeles::([A-Za-z_]\w*)/).compact_map do |match|
          "#{path.lchop(Modeles::SpecSupport::ROOT + "/")}:#{number} Modeles::#{match[1]}" unless allowed.includes?(match[1])
        end
        bare = code.scan(/(?<![\w:])(#{internals.join("|")})(?:::|\.)/).map do |match|
          "#{path.lchop(Modeles::SpecSupport::ROOT + "/")}:#{number} #{match[1]}"
        end
        qualified + bare
      end
    end
    leaks.should be_empty
  end

  it "n'utilise que des icônes de la planche de l'interface (ADR-005 D5)" do
    lucide = File.join(Modeles::SpecSupport::ROOT, "lib", "partiduo-ui-bulma", "icons", "lucide")
    known = Dir.glob(File.join(lucide, "*.svg")).map { |path| File.basename(path, ".svg") }
    known.should_not be_empty
    used = source_files("ui/bulma/templates/**/*.html").flat_map do |path|
      File.read(path).scan(/_icon\.html" with name="([a-z0-9-]+)"/).map { |match| "#{path.lchop(Modeles::SpecSupport::ROOT + "/")} #{match[1]}" }
    end
    used.should_not be_empty
    used.reject { |item| known.includes?(item.split(' ').last) }.should be_empty
  end

  it "écrit ses styles en propriétés logiques et avec les jetons du thème (sombre compris)" do
    css = source_files("ui/**/*.css").map { |path| File.read(path) }.join('\n')
    css.should_not be_empty
    physical = /(?:^|[\s;{])(?:margin|padding|border)-(?:left|right|top|bottom)\s*:|(?:^|[\s;{])(?:left|right|top|bottom|width|height|min-width|max-width|min-height|max-height)\s*:|text-align\s*:\s*(?:left|right)|float\s*:\s*(?:left|right)/
    css.gsub(/\/\*.*?\*\//m, "").scan(physical).map(&.[0]).should be_empty
    css.gsub(/\/\*.*?\*\//m, "").scan(/#[0-9a-fA-F]{3,8}\b|rgba?\(/).map(&.[0]).should be_empty
    css.should contain("focus-visible")
  end

  it "donne aux commandes de ses écrans une cible de 44 px et un nom accessible" do
    source_files("ui/bulma/templates/**/*.html").each do |path|
      html = File.read(path)
      html.scan(/<(?:button|a class="button)[^>]*>/).each do |match|
        {path, match[0].includes?("pd-touch")}.should eq({path, true})
      end
      html.scan(/<input(?![^>]*type="(?:hidden|checkbox)")[^>]*>/).each do |match|
        {path, match[0].includes?("id=")}.should eq({path, true})
      end
    end
  end
end
