## **THE NAME A PRINCIPAL GOES BY** (the Roc chat's auth design, section 1):
## a human chooses one at sign-up, and it "doesn't even have to be a real
## one" (Steve), but one is required; an agent's and a bot's names are held
## to the same rule. What the rule refuses is only what would hurt a reader
## or the store:
## - **UTF-8**, as every text is;
## - **trimmed of spaces at both ends,** then **1 to 64 bytes** (a byte
##   count, as every limit is: it protects the store, not a look);
## - **no control character**: ASCII's (a newline, a tab, DEL) and the C1
##   controls (U+0080 to U+009F), which would break a stored line or a page;
## - **no bidirectional control** (U+200E, U+200F, U+061C, U+202A to
##   U+202E, U+2066 to U+2069), which can make a name read as another one
##   reversed.
## Anything else goes: letters of any script, punctuation, emoji, spaces
## inside. Opaque, so a name that passed is the only kind there is. Pure.
import Ascii
import Bytes

DisplayName :: Str.{

	## Why a name is refused.
	Problem : [
		NotUtf8,
		Empty,
		TooLong,
		ControlCharacter,
		BidiControl,
	]

	## The name the bytes spell, as a form handed them.
	from_utf8 : List(U8) -> Try(DisplayName, DisplayName.Problem)
	from_utf8 = |bytes|
		match Str.from_utf8(bytes) {
			Ok(text) => DisplayName.from_str(text)
			Err(_) => Err(NotUtf8)
		}

	## The name `text` is, trimmed, when the rule takes it.
	from_str : Str -> Try(DisplayName, DisplayName.Problem)
	from_str = |text| {
		bytes = trim_spaces(Str.to_utf8(text))
		if bytes == [] {
			Err(Empty)
		} else if List.len(bytes) > max_bytes {
			Err(TooLong)
		} else if List.any(bytes, Ascii.is_control) or has_c1_control(bytes) {
			Err(ControlCharacter)
		} else if List.any(
			bidi_controls,
			|c| Bytes.find(bytes, { needle: Str.to_utf8(c), at: 0 }).is_ok(),
		) {
			Err(BidiControl)
		} else {
			match Str.from_utf8(bytes) {
				Ok(name) => Ok(DisplayName.(name))
				Err(_) => crash "DisplayName.from_str: UTF-8 trimmed of ASCII spaces is UTF-8"
			}
		}
	}

	## The name's text.
	to_str : DisplayName -> Str
	to_str = |DisplayName.(s)| s

	is_eq : _
}

## The most bytes a name may have.
max_bytes : U64
max_bytes = 64

## The first byte of every C1 control in UTF-8 (U+0080 to U+00BF begin with
## it), and the second bytes of the controls among them.
c1_lead : U8
c1_lead = 0xC2

c1_first : U8
c1_first = 0x80

c1_last : U8
c1_last = 0x9F

## The bidirectional controls: the marks, the embeddings and overrides, and
## the isolates.
bidi_controls : List(Str)
bidi_controls = [
	"\u(200E)",
	"\u(200F)",
	"\u(061C)",
	"\u(202A)",
	"\u(202B)",
	"\u(202C)",
	"\u(202D)",
	"\u(202E)",
	"\u(2066)",
	"\u(2067)",
	"\u(2068)",
	"\u(2069)",
]

## Spaces off both ends; only the ASCII space, since every other ASCII
## space is a control character, refused rather than trimmed.
trim_spaces : List(U8) -> List(U8)
trim_spaces = |bytes| {
	is_space = |c| c == ' '
	front = List.drop_first(bytes, Bytes.count_while(bytes, { keep: is_space, at: 0 }))
	List.drop_last(front, Bytes.count_back(front, { keep: is_space, kept: 0 }))
}

## A C1 control's two bytes are somewhere in `bytes`.
has_c1_control : List(U8) -> Bool
has_c1_control = |bytes|
	match bytes {
		[lead, second, ..] =>
			if lead == c1_lead and second >= c1_first and second <= c1_last {
				Bool.True
			} else {
				has_c1_control(List.drop_first(bytes, 1))
			}
		_ => Bool.False
	}

# ── tests

named : Str -> Try(Str, DisplayName.Problem)
named = |text| DisplayName.from_str(text).map_ok(DisplayName.to_str)

# Taken: anything readable, real or not, trimmed.
expect named("Steve") == Ok("Steve")
expect named("  Steve Howell  ") == Ok("Steve Howell")
expect named("x") == Ok("x")
expect named("🦊 fox of the woods") == Ok("🦊 fox of the woods")
expect named("Zoë, née Ünal") == Ok("Zoë, née Ünal")
expect named("名前") == Ok("名前")
expect named("a  b") == Ok("a  b")
expect named("Robert'); DROP TABLE") == Ok("Robert'); DROP TABLE")
expect named("<script>") == Ok("<script>")
expect named("role=admin name=x") == Ok("role=admin name=x")

# The length: 64 bytes, counted after the trim; 65 refused; a multi-byte
# character counts its bytes.
sixty_four : Str
sixty_four = Str.repeat("n", 64)

expect named(sixty_four) == Ok(sixty_four)
expect named("  ${sixty_four}  ") == Ok(sixty_four)
expect named(Str.repeat("n", 65)) == Err(TooLong)
expect named(Str.repeat("é", 32)) == Ok(Str.repeat("é", 32))
expect named(Str.repeat("é", 33)) == Err(TooLong)

# Empty, or spaces alone.
expect named("") == Err(Empty)
expect named("   ") == Err(Empty)

# Control characters: ASCII's at each end and inside, DEL, and C1's.
expect
	List.all(
		[
			"a\nb",
			"a\rb",
			"\tab",
			"ab\n",
			"a\u(0)b",
			"a\u(7F)b",
			"a\u(80)b",
			"a\u(85)b",
			"a\u(9F)b",
		],
		|bad| named(bad) == Err(ControlCharacter),
	)

# Next to the C1 range, and other two-byte characters, are fine.
expect named("a\u(A0)b") == Ok("a\u(A0)b")
expect named("a\u(7E)b") == Ok("a~b")

# Bidirectional controls, each one.
expect List.all(bidi_controls, |c| named("ab${c}cd") == Err(BidiControl))
expect named("\u(202E)nimda") == Err(BidiControl)

# Bytes that are not UTF-8.
expect DisplayName.from_utf8([0x61, 0xff]).map_ok(DisplayName.to_str) == Err(NotUtf8)
expect DisplayName.from_utf8(Str.to_utf8(" Ann ")).map_ok(DisplayName.to_str) == Ok("Ann")
