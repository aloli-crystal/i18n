require "yaml"
require "./i18n/version"

# Moteur i18n minimaliste, Crystal pur, zéro dépendance externe.
#
# Modèle de stockage : **un fichier YAML plat par langue** (pattern
# Rails/Ansible). Par exemple :
#
#     locales/fr.yml
#       greeting: "Bonjour %{name} !"
#       farewell: "Au revoir."
#
#     locales/en.yml
#       greeting: "Hello %{name}!"
#       farewell: "Goodbye."
#
# L'application consommatrice charge chaque fichier au démarrage :
#
#     require "i18n"
#     I18n.load("locales/fr.yml", locale: :fr)
#     I18n.load("locales/en.yml", locale: :en)
#     I18n.t(:greeting, name: "Philippe")
#     # => "Bonjour Philippe !" si LANG=fr*, "Hello Philippe!" sinon
#
# Fallback systématique sur l'anglais (`:en`) si la locale active n'a
# pas la clé demandée. Lève `KeyError` si aucune des deux n'a la clé.
#
# Détection de la locale via `LC_ALL` / `LC_MESSAGES` / `LANG` (deux
# premières lettres). Override manuel via `I18n.locale = :xx`.
module I18n
  # Table interne : clé de message → locale → texte. Tout en `String`
  # (les clés viennent du YAML et les locales de `LANG`) ; pas de
  # symboles pour éviter la conversion inverse impossible côté regex
  # (Crystal n'a pas `String#to_sym`).
  alias Table = Hash(String, Hash(String, String))

  @@messages : Table = Table.new
  @@locale_override : String? = nil

  # Charge un fichier YAML plat (clés au niveau racine, valeurs string)
  # dans la locale `locale` (acceptée comme `Symbol` `:fr` ou `String`
  # `"fr"`, stockée en string en interne). Les appels successifs sur la
  # même locale fusionnent ; une clé déjà présente est écrasée.
  #
  # Lève `ArgumentError` si le fichier n'est pas un mapping YAML plat.
  def self.load(path : String, locale : Symbol | String) : Nil
    loc = locale.to_s
    content = File.read(path)
    parsed = YAML.parse(content)
    mapping = parsed.as_h? || raise ArgumentError.new(
      "I18n : #{path} n'est pas un mapping YAML (clé → valeur au niveau racine attendu)"
    )

    mapping.each do |key_any, value_any|
      key = key_any.as_s
      text = value_any.as_s? || raise ArgumentError.new(
        "I18n : la valeur de #{key.inspect} dans #{path} n'est pas une string"
      )
      current = @@messages.fetch(key) { Hash(String, String).new }
      current[loc] = text
      @@messages[key] = current
    end
  end

  # Remet la table à zéro (utile en tests).
  def self.reset : Nil
    @@messages = Table.new
    @@locale_override = nil
  end

  # Force une locale, ignore la détection par ENV. `nil` = reprendre
  # la détection automatique. Accepte `Symbol` ou `String`.
  def self.locale=(loc : Symbol | String | Nil) : String?
    @@locale_override = loc.try(&.to_s)
  end

  # Retourne la locale active (String). Ordre :
  # . override manuel (`I18n.locale = :xx`)
  # . `LC_ALL` / `LC_MESSAGES` / `LANG` → 2 premières lettres
  # . `"en"` par défaut
  def self.locale : String
    return @@locale_override.not_nil! if @@locale_override
    detect_locale
  end

  # Traduit une clé dans la locale active, avec interpolation des
  # `%{placeholder}` par les `params` nommés. Fallback sur `"en"` si la
  # locale active n'a pas la clé. Lève `KeyError` si même `"en"` manque.
  #
  # La clé est acceptée comme symbole (style Ruby : `t(:greeting)`) ou
  # comme string pour souplesse.
  def self.t(key : Symbol | String, **params) : String
    key_str = key.to_s
    entry = @@messages[key_str]? || raise KeyError.new(
      "I18n : clé inconnue #{key_str.inspect} — avez-vous chargé vos fichiers locales via I18n.load ?"
    )
    template = entry[locale]? || entry["en"]? || raise KeyError.new(
      "I18n : clé #{key_str.inspect} absente pour locale #{locale.inspect} et du fallback \"en\""
    )
    interpolate(template, params)
  end

  private def self.detect_locale : String
    {"LC_ALL", "LC_MESSAGES", "LANG"}.each do |var|
      v = ENV[var]?
      next if v.nil? || v.empty?
      return v[0, 2].downcase
    end
    "en"
  end

  # `**params` est une NamedTuple en Crystal : on matérialise en Hash
  # de String pour pouvoir lookuper par nom runtime (les NamedTuple
  # n'acceptent que des clés littérales au compile time).
  private def self.interpolate(template : String, params) : String
    params_hash = {} of String => String
    params.each { |k, v| params_hash[k.to_s] = v.to_s }
    template.gsub(/%\{(\w+)\}/) do
      name = $1
      params_hash[name]? || "%{#{name}}"
    end
  end
end
