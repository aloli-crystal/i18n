require "./spec_helper"

private def write_yaml(content : String) : String
  path = File.tempname(prefix: "i18n-spec-", suffix: ".yml")
  File.write(path, content)
  path
end

describe I18n do
  it "expose une version" do
    I18n::VERSION.should eq("0.1.2")
  end

  describe ".load + .t" do
    it "charge un YAML plat et traduit dans la locale active" do
      fr_path = write_yaml(%({"greeting": "Bonjour %{name} !", "farewell": "Au revoir."}))
      begin
        I18n.load(fr_path, locale: :fr)
        I18n.locale = :fr
        I18n.t(:greeting, name: "Philippe").should eq("Bonjour Philippe !")
        I18n.t(:farewell).should eq("Au revoir.")
      ensure
        File.delete(fr_path)
      end
    end

    it "fusionne les entrées entre plusieurs locales" do
      fr = write_yaml(%({"greeting": "Bonjour !"}))
      en = write_yaml(%({"greeting": "Hello!"}))
      begin
        I18n.load(fr, locale: :fr)
        I18n.load(en, locale: :en)
        I18n.locale = :fr
        I18n.t(:greeting).should eq("Bonjour !")
        I18n.locale = :en
        I18n.t(:greeting).should eq("Hello!")
      ensure
        File.delete(fr); File.delete(en)
      end
    end

    it "retombe sur :en si la locale active n'a pas la clé" do
      en = write_yaml(%({"only_en": "Only in English."}))
      begin
        I18n.load(en, locale: :en)
        I18n.locale = :fr
        I18n.t(:only_en).should eq("Only in English.")
      ensure
        File.delete(en)
      end
    end

    it "lève KeyError si la clé n'existe ni dans la locale active ni en :en" do
      fr = write_yaml(%({"only_fr": "Seulement en français."}))
      begin
        I18n.load(fr, locale: :fr)
        I18n.locale = :en
        expect_raises(KeyError, /only_fr/) { I18n.t(:only_fr) }
      ensure
        File.delete(fr)
      end
    end

    it "lève KeyError si la clé est totalement inconnue" do
      I18n.locale = :en
      expect_raises(KeyError, /inconnu/) { I18n.t(:jamais_enregistre) }
    end

    it "interpole plusieurs placeholders" do
      fr = write_yaml(%({"line": "Bootstrap de %{host} sur %{disk}."}))
      begin
        I18n.load(fr, locale: :fr)
        I18n.locale = :fr
        I18n.t(:line, host: "loulou", disk: "/dev/sda")
          .should eq("Bootstrap de loulou sur /dev/sda.")
      ensure
        File.delete(fr)
      end
    end

    it "laisse un placeholder non fourni tel quel" do
      fr = write_yaml(%({"line": "Bonjour %{name}."}))
      begin
        I18n.load(fr, locale: :fr)
        I18n.locale = :fr
        I18n.t(:line).should eq("Bonjour %{name}.")
      ensure
        File.delete(fr)
      end
    end

    it "les appels successifs sur la même locale s'additionnent, la clé dupliquée écrase" do
      fr1 = write_yaml(%({"a": "A1", "b": "B1"}))
      fr2 = write_yaml(%({"a": "A2", "c": "C2"}))
      begin
        I18n.load(fr1, locale: :fr)
        I18n.load(fr2, locale: :fr)
        I18n.locale = :fr
        I18n.t(:a).should eq("A2")
        I18n.t(:b).should eq("B1")
        I18n.t(:c).should eq("C2")
      ensure
        File.delete(fr1); File.delete(fr2)
      end
    end

    it "rejette un YAML qui n'est pas un mapping racine" do
      bad = write_yaml("- liste\n- au\n- lieu\n")
      begin
        expect_raises(ArgumentError, /mapping YAML/) do
          I18n.load(bad, locale: :fr)
        end
      ensure
        File.delete(bad)
      end
    end
  end

  describe ".locale" do
    it "détecte via LANG (deux premières lettres)" do
      I18n.locale = nil
      previous = ENV["LANG"]?
      begin
        ENV["LANG"] = "fr_FR.UTF-8"
        I18n.locale.should eq("fr")
        ENV["LANG"] = "de_DE.UTF-8"
        I18n.locale.should eq("de")
      ensure
        if previous
          ENV["LANG"] = previous
        else
          ENV.delete("LANG")
        end
      end
    end

    it "retombe sur 'en' sans variable d'env détectable" do
      I18n.locale = nil
      saved = {} of String => String?
      {"LC_ALL", "LC_MESSAGES", "LANG"}.each { |v| saved[v] = ENV[v]?; ENV.delete(v) }
      begin
        I18n.locale.should eq("en")
      ensure
        saved.each { |v, val| val ? (ENV[v] = val) : ENV.delete(v) }
      end
    end

    it "accepte un override manuel via locale= (Symbol ou String)" do
      I18n.locale = :zh
      I18n.locale.should eq("zh")
      I18n.locale = "pt"
      I18n.locale.should eq("pt")
    end
  end
end
