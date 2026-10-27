## HTML'S TWO SAFETIES (zig-webbox html.zig): text escaped for an element or
## an attribute, and a blob made safe inside an inline `<script>`.
import Bytes

Html := [].{

	## htmlEscape: `&`, `'`, `<`, `>` and `"` as entities.
	escape : List(U8) -> List(U8)
	escape = |s| List.join(
		List.map(
			s,
			|c|
				match c {
					'&' => Str.to_utf8("&amp;")
					'\'' => Str.to_utf8("&#39;")
					'<' => Str.to_utf8("&lt;")
					'>' => Str.to_utf8("&gt;")
					'"' => Str.to_utf8("&#34;")
					_ => [c]
				},
		),
	)

	## scriptSafe: every `</` as `<\/`, the one sequence that could end the
	## element early.
	script_safe : List(U8) -> List(U8)
	script_safe = |s| List.join(List.intersperse(Bytes.split_seq(s, ['<', '/']), ['<', '\\', '/']))
}
