## **AN UPLOAD, AS IT IS SERVED** (angry-gopher chat_upload.zig, metal-vmm
## QUEUE 291): the type its stored name says, and which of its bytes a
## `Range` asks for. The host carries the answer out (Host.serve_upload!).
## Pure.
import Bytes
import ZigText

Upload := [].{

	## uploadContentType: a stored name is 32 lowercase hex digits, a dot and
	## a type the chat takes; its MIME type, or `NotAnUpload` (which is also
	## the path check on the file's segment: no other name is served).
	content_type : Str -> Try(Str, [NotAnUpload])
	content_type = |name| {
		bytes = name.to_utf8()
		hex = List.take_first(bytes, 32)
		if List.len(bytes) > 33 and List.get(bytes, 32) == Ok('.') and List.all(hex, is_hex) {
			match Str.from_utf8(List.drop_first(bytes, 33)) {
				Ok(ext) =>
					match List.find_first(types, |t| t.ext == ext) {
						Ok(t) => Ok(t.mime)
						Err(_) => Err(NotAnUpload)
					}
				Err(_) => Err(NotAnUpload)
			}
		} else {
			Err(NotAnUpload)
		}
	}

	## parseRange: the first range of a `bytes=` header of a file of `size`
	## bytes, its first and last byte, at most `window` of them; or
	## `Unsatisfiable` (an empty file, a range past its end, reversed, a
	## suffix of none, or a header that is no byte range).
	range : List(U8), U64 -> Try({ first : U64, last : U64 }, [Unsatisfiable])
	range = |header, size|
		match (size, Bytes.cut_seq(header, Str.to_utf8("bytes="))) {
			(0, _) => Err(Unsatisfiable)
			(_, Ok(([], spec_all))) => {
				spec = match Bytes.cut_seq(spec_all, [',']) {
					Ok((before, _)) => before
					Err(NotFound) => spec_all
				}
				match Bytes.cut_seq(spec, ['-']) {
					Ok((left, right)) => from_to(
						trim_spaces(left),
						trim_spaces(right),
						size,
					)
					Err(NotFound) => Err(Unsatisfiable)
				}
			}
			_ => Err(Unsatisfiable)
		}

	## The most one range answers, 8 MiB (chat_upload `range_window`): a
	## player asks again for the rest.
	window : U64
	window = 8 * 1024 * 1024
}

## The range `left-right` of `size` bytes, cut to the window.
from_to : List(U8), List(U8), U64 -> Try({ first : U64, last : U64 }, [Unsatisfiable])
from_to = |
	left,
	right,
	size,
| {
	whole = if left == [] {
		# A suffix: the last N bytes.
		match ZigText.parse_u64(right) {
			Ok(0) | Err(_) => Err(Unsatisfiable)
			Ok(n) => Ok({ first: if n >= size 0 else size - n, last: size - 1 })
		}
	} else {
		match ZigText.parse_u64(left) {
			Err(_) => Err(Unsatisfiable)
			Ok(first) if first >= size => Err(Unsatisfiable)
			Ok(first) =>
				if right == [] {
					Ok({ first, last: size - 1 })
				} else {
					match ZigText.parse_u64(right) {
						Ok(end) if end >= first => Ok({
							first,
							last: if end < size - 1 end else size - 1,
						})
						_ => Err(Unsatisfiable)
					}
				}
		}
	}
	match whole {
		Ok(r) => Ok({
			first: r.first,
			last: if r.last < r.first + Upload.window - 1 r.last else r.first + Upload.window - 1,
		})
		Err(Unsatisfiable) => Err(Unsatisfiable)
	}
}

## Spaces off both ends (the Zig's trim of " ").
trim_spaces : List(U8) -> List(U8)
trim_spaces = |b|
	match b {
		[' ', .. as rest] => trim_spaces(rest)
		_ =>
			match List.last(b) {
				Ok(' ') => trim_spaces(List.drop_last(b, 1))
				_ => b
			}
	}

is_hex : U8 -> Bool
is_hex = |c| (c >= '0' and c <= '9') or (c >= 'a' and c <= 'f')

## The types the chat takes (chat_upload `accepted`): each stored name's
## extension and the type it is served as.
types : List({ ext : Str, mime : Str })
types = [
	{ ext: "png", mime: "image/png" },
	{ ext: "jpg", mime: "image/jpeg" },
	{ ext: "gif", mime: "image/gif" },
	{ ext: "webp", mime: "image/webp" },
	{ ext: "mp4", mime: "video/mp4" },
	{ ext: "webm", mime: "video/webm" },
	{ ext: "mov", mime: "video/quicktime" },
]

expect Upload.content_type("0123456789abcdef0123456789abcdef.png") == Ok("image/png")
expect Upload.content_type("0123456789abcdef0123456789abcdeF.png") == Err(NotAnUpload)
expect Upload.content_type("0123456789abcdef0123456789abcdef.exe") == Err(NotAnUpload)
expect Upload.content_type("a.png") == Err(NotAnUpload)
expect Upload.range("bytes=0-3".to_utf8(), 24) == Ok({ first: 0, last: 3 })
expect Upload.range("bytes=-4".to_utf8(), 24) == Ok({ first: 20, last: 23 })
expect Upload.range("bytes= 1 - 2 ".to_utf8(), 24) == Ok({ first: 1, last: 2 })
expect Upload.range("bytes=2-4,8-9".to_utf8(), 24) == Ok({ first: 2, last: 4 })
expect Upload.range("bytes=4-2".to_utf8(), 24) == Err(Unsatisfiable)
expect Upload.range("bytes=-0".to_utf8(), 24) == Err(Unsatisfiable)
expect Upload.range("bytes=0-1".to_utf8(), 0) == Err(Unsatisfiable)
expect Upload.range("bytes=0-".to_utf8(), 20000000) == Ok({ first: 0, last: Upload.window - 1 })

# chat_upload's parseRange tests, here since its Zig is gone (metal-vmm
# QUEUE 291): RFC 9110 §14.1.2's edges and the window's.
expect Upload.range("bytes=999-".to_utf8(), 1000) == Ok({ first: 999, last: 999 })
expect Upload.range("bytes=1000-".to_utf8(), 1000) == Err(Unsatisfiable)
expect Upload.range("bytes=0-".to_utf8(), 1) == Ok({ first: 0, last: 0 })
expect Upload.range("bytes=1-".to_utf8(), 1) == Err(Unsatisfiable)
expect Upload.range("bytes=0-1000".to_utf8(), 1000) == Ok({ first: 0, last: 999 })
expect Upload.range("bytes=500-499".to_utf8(), 1000) == Err(Unsatisfiable)
expect Upload.range("bytes=-999".to_utf8(), 1000) == Ok({ first: 1, last: 999 })
expect Upload.range("bytes=-1001".to_utf8(), 1000) == Ok({ first: 0, last: 999 })
expect Upload.range("0-100".to_utf8(), 1000) == Err(Unsatisfiable)
expect Upload.range("bytes=abc".to_utf8(), 1000) == Err(Unsatisfiable)
expect Upload.range(
	"bytes=5-${(5 + Upload.window - 1).to_str()}".to_utf8(),
	64 * 1024 * 1024,
) == Ok({ first: 5, last: 5 + Upload.window - 1 })
expect Upload.range(
	"bytes=5-${(5 + Upload.window).to_str()}".to_utf8(),
	64 * 1024 * 1024,
) == Ok({ first: 5, last: 5 + Upload.window - 1 })
