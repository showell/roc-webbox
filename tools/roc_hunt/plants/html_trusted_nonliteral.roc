## Plants for `html_trusted_nonliteral`: parsed, never compiled.
Plants := [].{
	fires_variable : Str -> Html
	fires_variable = |name| Html.trusted(name)

	fires_interpolated : Str -> Html
	fires_interpolated = |name| Html.trusted("<b>${name}</b>")

	fires_call : List(U8) -> Html
	fires_call = |name| Html.trusted(Str.from_utf8_lossy(name))

	fires_host_markup : List(U8) -> Html
	fires_host_markup = |src| Html.host_markup(src)

	fires_twin_json : List(U8) -> Html.ScriptJson
	fires_twin_json = |json| Html.twin_script_json(json)

	fires_passed : List(Str) -> List(Html)
	fires_passed = |names| List.map(names, Html.trusted)

	quiet_literal : Html
	quiet_literal = Html.trusted("<p>")

	quiet_multiline : Html
	quiet_multiline = Html.trusted(
		\\<style>
		\\</style>
	)

	quiet_escape : List(U8) -> Html
	quiet_escape = |text| Html.escape(text)
}
