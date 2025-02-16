defmodule Cldr.LocaleDisplay do
  @moduledoc """
  Implements the [CLDR locale display name algorithm](https://unicode-org.github.io/cldr/ldml/tr35-general.html#locale_display_name_algorithm) to format
  a `t:Cldr.LanguageTag` structs for presentation uses.

  """

  @doc false
  def cldr_backend_provider(config) do
    Cldr.LocaleDisplay.Backend.define_locale_display_module(config)
  end

  import Cldr.LanguageTag, only: [empty?: 1]

  alias Cldr.LanguageTag

  @basic_tag_order [:language, :script, :territory, :language_variants]
  @extension_order [:transform, :locale, :extensions]
  @omit_script_if_only_one false

  @type display_options :: [
          {:compound_locale, boolean()},
          {:prefer, atom()},
          {:locale, Cldr.Locale.locale_name() | Cldr.LanguageTag.t()},
          {:backend, Cldr.backend()}
        ]

  @doc """
  Returns a localised display name for a
  locale.

  UI applications often have a requirement
  to present locale choices to an end user.

  This function takes a `t.Cldr.LanguageTag`
  and using the [CLDR locale display name algorithm](https://unicode-org.github.io/cldr/ldml/tr35-general.html#locale_display_name_algorithm)
  produces a string suitable for presentation.

  ## Arguments

  * `language_tag` is any `t:Cldr.LanguageTag` or
    a binary locale name.

  * `options` is a keyword list of options.

  ## Options

  * `:compound_locale` is a boolean indicating
    if the combination of language, script and territory
    should be used to resolve a language name.
    The default is `true`.

  * `:prefer` signals the preferred name for
    a subtag when there are alternatives.
    The default is `:default`. Few subtags
    provide alternative renderings. Some of
    the alternative preferences are`:short`,
    `:long`, `:menu` and `:variant`.

  * `:locale` is a `t:Cldr.LanguageTag` or any valid
    locale name returned by `Cldr.known_locale_names/1`.

  * `:backend` is any module that includes `use Cldr` and therefore
    is a `Cldr` backend module. The default is `Cldr.default_backend!/0`.

  ## Returns

  * `{:ok, string}` representating a name
    suitable for presentation purposes or

  * `{:error, {exception, reason}}`

  ## Examples

      iex> Cldr.LocaleDisplay.display_name "en"
      {:ok, "English"}

      iex> Cldr.LocaleDisplay.display_name "en-US"
      {:ok, "American English"}

      iex> Cldr.LocaleDisplay.display_name "en-US", compound_locale: false
      {:ok, "English (United States)"}

      iex> Cldr.LocaleDisplay.display_name "en-US-u-ca-gregory-cu-aud"
      {:ok, "American English (Gregorian Calendar, Currency: A$)"}

      iex> Cldr.LocaleDisplay.display_name "en-US-u-ca-gregory-cu-aud", locale: "fr"
      {:ok, "anglais américain (calendrier grégorien, devise : A$)"}

      iex> Cldr.LocaleDisplay.display_name "nl-BE"
      {:ok, "Flemish"}

      iex> Cldr.LocaleDisplay.display_name "nl-BE", compound_locale: false
      {:ok, "Dutch (Belgium)"}

  """
  @spec display_name(Cldr.Locale.locale_name() | Cldr.LanguageTag.t(), display_options()) ::
          {:ok, String.t()} | {:error, {module(), String.t()}}

  def display_name(language_tag, options \\ [])

  def display_name(language_tag, options) when is_binary(language_tag) do
    {_in_locale, backend} = Cldr.locale_and_backend_from(options)
    options = Keyword.put_new(options, :add_likely_subtags, false)

    with {:ok, locale} <- Cldr.Locale.canonical_language_tag(language_tag, backend, options) do
      display_name(locale, options)
    end
  end

  def display_name(%LanguageTag{} = language_tag, options) do
    {in_locale, backend} = Cldr.locale_and_backend_from(options)
    compound_locale? = !!Keyword.get(options, :compound_locale, true)
    prefer = Keyword.get(options, :prefer, :default)

    with {:ok, in_locale} <- Cldr.validate_locale(in_locale, backend) do
      options = Keyword.put(options, :locale, in_locale)

      {:ok, display_names} =
        Module.concat(in_locale.backend, :LocaleDisplay).display_names(in_locale)

      match_fun = &language_match_fun(&1, &2, display_names.language)

      {language_name, matched_tags} =
        first_match(language_tag, match_fun, @omit_script_if_only_one, compound_locale?, prefer)

      subtag_names =
        language_tag
        |> subtag_names(@basic_tag_order -- matched_tags, display_names, prefer)
        |> List.flatten()
        |> join_subtags(display_names)

      language_tag = merge_extensions_and_private_use(language_tag)

      extension_names =
        @extension_order
        |> Enum.map(&Cldr.DisplayName.display_name(Map.fetch!(language_tag, &1), options))
        |> Enum.reject(&empty?/1)
        |> join_subtags(display_names)

      {:ok, format_display_name(language_name, subtag_names, extension_names, display_names)}
    end
  end

  @doc """
  Returns a localised display name for a
  locale.

  UI applications often have a requirement
  to present locale choices to an end user.

  This function takes a `t.Cldr.LanguageTag`
  and using the [CLDR locale display name algorithm](https://unicode-org.github.io/cldr/ldml/tr35-general.html#locale_display_name_algorithm)
  produces a string suitable for presentation.

  ## Arguments

  * `language_tag` is any `t:Cldr.LanguageTag` or
    a binary locale name.

  * `options` is a keyword list of options.

  ## Options

  * `:compound_locale` is a boolean indicating
    if the combination of language, script and territory
    should be used to resolve a language name.
    The default is `true`.

  * `:prefer` signals the preferred name for
    a subtag when there are alternatives.
    The default is `:default`. Few subtags
    provide alternative renderings. Some of
    the alternative preferences are`:short`,
    `:long`, `:menu` and `:variant`.

  * `:locale` is a `t:Cldr.LanguageTag` or any valid
    locale name returned by `Cldr.known_locale_names/1`.

  * `:backend` is any module that includes `use Cldr` and therefore
    is a `Cldr` backend module. The default is `Cldr.default_backend!/0`.

  ## Returns

  * a string representation of the language tag
    suitable for presentation purposes or

  * raises an exception.

  ## Examples

      iex> Cldr.LocaleDisplay.display_name! "en"
      "English"

      iex> Cldr.LocaleDisplay.display_name! "en-US"
      "American English"

      iex> Cldr.LocaleDisplay.display_name! "en-US", compound_locale: false
      "English (United States)"

      iex> Cldr.LocaleDisplay.display_name! "en-US-u-ca-gregory-cu-aud"
      "American English (Gregorian Calendar, Currency: A$)"

      iex> Cldr.LocaleDisplay.display_name! "en-US-u-ca-gregory-cu-aud", locale: "fr"
      "anglais américain (calendrier grégorien, devise : A$)"

  """
  @spec display_name!(Cldr.Locale.locale_name() | Cldr.LanguageTag.t(), display_options()) ::
          String.t() | no_return()

  def display_name!(language_tag, options \\ []) do
    case display_name(language_tag, options) do
      {:ok, locale} -> locale
      {:error, {exception, reason}} -> raise exception, reason
    end
  end

  defp merge_extensions_and_private_use(%LanguageTag{private_use: []} = language_tag) do
    language_tag
  end

  defp merge_extensions_and_private_use(%LanguageTag{} = language_tag) do
    extensions = Map.put_new(language_tag.extensions, "x", language_tag.private_use)
    Map.put(language_tag, :extensions, extensions)
  end

  # If matching on the compound locale then we
  # don't need to take any action
  defp first_match(language_tag, match_fun, omit_script_if_only_one?, true, prefer) do
    {language_name, matched_tags} =
      Cldr.Locale.first_match(language_tag, match_fun, omit_script_if_only_one?)

    {get_display_preference(language_name, prefer), matched_tags}
  end

  # If we don't want a compound language then we need to omit
  # the territory when matching but restore is afterwards so
  # its generated as a subtag
  @reinstate_subtags [:territory, :script]

  defp first_match(language_tag, match_fun, omit_script_if_only_one?, false, prefer) do
    language_tag = Enum.reduce(@reinstate_subtags, language_tag, fn key, tag ->
      Map.put(tag, key, nil)
    end)

    {language_name, matched_tags} =
      Cldr.Locale.first_match(language_tag, match_fun, omit_script_if_only_one?)

    {get_display_preference(language_name, prefer), matched_tags -- @reinstate_subtags}
  end

  defp format_display_name(language_name, [], [], _display_names) do
    language_name
  end

  defp format_display_name(language_name, subtag_names, extension_names, display_names) do
    locale_pattern = get_in(display_names, [:locale_display_pattern, :locale_pattern])

    subtags =
      [subtag_names, extension_names]
      |> Enum.reject(&empty?/1)
      |> join_subtags(display_names)

    [language_name, subtags]
    |> Cldr.Substitution.substitute(locale_pattern)
    |> :erlang.iolist_to_binary()
  end

  defp subtag_names(_locale, [], _display_names, _prefer) do
    []
  end

  defp subtag_names(locale, subtags, display_names, prefer) do
    subtags
    |> Enum.map(&get_display_name(locale, display_names, &1, prefer))
    |> Enum.reject(&empty?/1)
  end

  defp get_display_name(locale, display_names, subtag, prefer) do
    case Map.fetch!(locale, subtag) do
      [_ | _] = subtags ->
        Enum.map(subtags, fn value -> get_in(display_names, [subtag, value]) end)
        |> Enum.sort()

      subtag_value ->
        get_in(display_names, [subtag, subtag_value])
    end
    |> get_display_preference(prefer)
  end

  @doc false
  def get_display_preference(nil, _preference) do
    nil
  end

  def get_display_preference(value, _preference) when is_binary(value) do
    value
  end

  def get_display_preference(value, _preference) when is_atom(value) do
    to_string(value)
  end

  def get_display_preference(values, preference) when is_list(values) do
    Enum.map(values, &get_display_preference(&1, preference))
  end

  def get_display_preference(values, preference) when is_map(values) do
    Map.get(values, preference) || Map.fetch!(values, :default)
  end

  defp join_subtags([], _display_names) do
    []
  end

  defp join_subtags([field], _display_names) do
    [field]
  end

  defp join_subtags(fields, display_names) do
    join_pattern = get_in(display_names, [:locale_display_pattern, :locale_separator])
    Enum.reduce(fields, &Cldr.Substitution.substitute([&2, &1], join_pattern))
  end

  defp language_match_fun(locale_name, matched_tags, language_names) do
    if display_name = Map.get(language_names, locale_name) do
      {display_name, matched_tags}
    else
      nil
    end
  end

  @doc false
  def replace_parens_with_brackets(value) when is_binary(value) do
    value
    |> String.replace("(", "[")
    |> String.replace(")", "]")
  end

  # Joins field values together using the
  # localised format

  @doc false
  def join_field_values([], _display_names) do
    []
  end

  def join_field_values(fields, display_names) do
    join_pattern = get_in(display_names, [:locale_display_pattern, :locale_separator])
    Enum.reduce(fields, &Cldr.Substitution.substitute([&2, &1], join_pattern))
  end

  defimpl Cldr.DisplayName, for: Cldr.LanguageTag do
    def display_name(language_tag, options) do
      Cldr.LocaleDisplay.display_name!(language_tag, options)
    end
  end

  defimpl Cldr.DisplayName, for: Map do
    def display_name(map, _options) when map == %{} do
      ""
    end

    def display_name(map, options) do
      Cldr.LocaleDisplay.Extension.display_name(map, options)
    end
  end
end
