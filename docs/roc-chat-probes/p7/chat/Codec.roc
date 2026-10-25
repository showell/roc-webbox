Codec :: [].{
	sep : Str
	sep = "\n\n-------------\n"

	## Body lines that start with the separator's dashes get escaped.
	escape : Str -> Str
	escape = |body| Str.replace_each(body, "\n-------------", "\n\\-------------")

	blocks : Str -> List(Str)
	blocks = |text| if Str.is_empty(text) [] else Str.split_on(text, sep)
}

expect Codec.blocks("a\n\n-------------\nb") == ["a", "b"]
expect Codec.blocks("") == []
expect Codec.escape("x\n-------------y") == "x\n\\-------------y"
