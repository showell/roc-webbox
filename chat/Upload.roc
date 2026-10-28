## **AN UPLOAD, AS IT IS SERVED** (angry-gopher chat_upload.zig, metal-vmm
## QUEUE 291): the type its stored name says, and which of its bytes a
## `Range` asks for, and the route itself (metal-vmm QUEUE 300): an
## upload's POST and GET, the host reading the form and serving the bytes.
import pf.Chat
import pf.Host
import Bytes
import Files
import Paths
import JsonOut
import Limits
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

	## A stored extension's kind: its name, its noun in a refusal, and the
	## largest file of it the chat takes (UploadKind.cap); `NotTaken` for
	## one the chat does not take.
	kind_of : List(U8) -> Try(
		{
			name : Str,
			noun : Str,
			cap : U64,
		},
		[NotTaken],
	)
	kind_of = |ext|
		match List.find_first(types, |t| t.ext.to_utf8() == ext) {
			Ok(t) if t.mime.starts_with("image/") => Ok({
				name: "image",
				noun: "Image",
				cap: Limits.image_max,
			})
			Ok(_) => Ok({
				name: "video",
				noun: "Screencast",
				cap: Limits.video_max,
			})
			Err(_) => Err(NotTaken)
		}

	## The 415 for a file of a type the chat takes not.
	unsupported : Str
	unsupported = "unsupported file type (images: png, jpeg, gif, webp; video: mp4, webm, mov)\n"

	## The 403 for a member whose lifetime allowance would be passed.
	allowance_spent : Str
	allowance_spent = {
		gb = (Limits.upload_lifetime // (1024 * 1024 * 1024)).to_str()
		"Upload limit reached — you've used your ${gb} GB upload allowance.\n"
	}

	## The 413 for a file past its kind's cap (`noun`, `cap` as kind_of's).
	too_large : { noun : Str, cap : U64 } -> Str
	too_large = |kind| {
		mb = (kind.cap // (1024 * 1024)).to_str()
		"${kind.noun} too large — the limit is ${mb} MB.\n"
	}

	## handleUpload's answer: where the file is now, the client's name for
	## it as text (a byte not UTF-8 its U+FFFD), its kind; no size yet.
	stored_answer : {
		url : Str,
		filename : List(U8),
		kind : Str,
	} -> List(U8)
	stored_answer = |a|
		JsonOut.object([
			("url", JsonOut.string(a.url)),
			("name", JsonOut.lossy(a.filename)),
			("kind", JsonOut.string(a.kind)),
			("width", JsonOut.number(0)),
			("height", JsonOut.number(0)),
		]).bytes()

	## The most one range answers, 8 MiB (chat_upload `range_window`): a
	## player asks again for the rest.
	window : U64
	window = 8 * 1024 * 1024

	## **AN UPLOAD'S POST** (chat_upload `handleUpload`, metal-vmm QUEUE 292):
	## the form read and its file's type sniffed by the host, which holds the
	## bytes; then here, in the Zig's order, a type the chat does not take, a
	## file past its kind's cap, the member's allowance, the file stored, and
	## the answer the compose box reads.
	post! : Chat.Request, Paths.TopicAt => Chat.Answer
	post! = |req, at|
		if req.method != Post {
			Chat.not_allowed(Post)
		} else {
			form = Host.read_upload!({})
			match form.status {
				Answered => Chat.answered
				NoFile => {
					Host.refuse_upload!(Malformed, "no file\n".to_utf8())
					Chat.answered
				}
				Unsupported => Chat.respond(
					415,
					[],
					unsupported.to_utf8(),
				)
				Read =>
					match kind_of(form.ext) {
						Err(NotTaken) => crash "Upload.post!: the host sniffed a type not taken"
						Ok(kind) =>
							if form.size > kind.cap {
								Host.refuse_upload!(
									TooLarge,
									too_large({ noun: kind.noun, cap: kind.cap }).to_utf8(),
								)
								Chat.answered
							} else {
								keep!(form, { kind: kind.name, at })
							}
					}
			}
		}

	## **AN UPLOAD SERVED** (chat_upload `serveUpload`, metal-vmm QUEUE 291):
	## a GET's or a HEAD's, of a name an upload has (`file`), typed by it;
	## whole, or the range asked for, or the 416 for one that cannot be. The
	## host serves the bytes (Host.serve_upload!).
	serve! : Chat.Request, { at : Paths.TopicAt, file : Str } => Chat.Answer
	serve! = |req, { at, file }|
		if req.method != Get and req.method != Head {
			Chat.not_allowed(Get)
		} else {
			match content_type(file) {
				Err(NotAnUpload) => Chat.not_found
				Ok(typed) => {
					path = Paths.upload_path(at, file)
					match Files.stat!(path) {
						Err(Missing) => Chat.not_found
						Err(Failed) => Chat.answered
						Ok(st) => {
							part = match Host.read_header!("range".to_utf8()) {
								[] => Whole({ first: 0, last: 0 })
								[asked, ..] =>
									match range(asked, st.size) {
										Ok(r) => Range(r)
										Err(Unsatisfiable) => Unsatisfiable({ first: 0, last: 0 })
									}
							}
							(kind, r) = match part {
								Whole(span) => (Whole, span)
								Range(span) => (Range, span)
								Unsatisfiable(span) => (Unsatisfiable, span)
							}
							served = Host.serve_upload!({
								first: r.first,
								last: r.last,
								size: st.size,
								content_type: typed.to_utf8(),
								path: path.bytes(),
								part: kind,
							})
							match served {
								Served => Chat.answered
								# Gone since its stat: nothing was answered.
								Gone => Chat.not_found
							}
						}
					}
				}
			}
		}

}

## The allowance spent on the file, then the file stored and its answer.
keep! : {
	size : U64,
	ext : List(U8),
	filename : List(U8),
	status : _,
},
{ kind : Str, at : Paths.TopicAt } => Chat.Answer
keep! = |form, { kind, at }|
	match Host.reserve_upload!(form.size) {
		Failed => Chat.answered
		Refused => Chat.respond(
			403,
			[],
			Upload.allowance_spent.to_utf8(),
		)
		Reserved => {
			stored = Host.store_upload!(Paths.uploads_folder(at).bytes(), form.ext)
			name = Str.from_utf8_lossy(stored.name)
			match stored.status {
				Failed => Chat.answered
				Stored => Chat.respond(
					200,
					Chat.json,
					Upload.stored_answer({
						url: "${Paths.ConvKey.base(at.key)}/${at.topic}/uploads/${name}",
						filename: form.filename,
						kind,
					}),
				)
			}
		}
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
