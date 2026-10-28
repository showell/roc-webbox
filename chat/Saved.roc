## **WHAT A MEMBER SAVED, READ BACK FROM THEIR READING LIST** (angry-gopher
## reading_list.zig `parseRefs`, metal-vmm QUEUE 273): every jump URL the
## save wrote, `/chat/c/<conv>/<topic>#msg-<id>` and
## `/channel/<conv>/<topic>#msg-<id>`, the first prefix's all before the
## second's. **LENIENT**: the member edits this doc freely, so a URL of any
## other shape is passed over, never an error, and bytes that are not
## UTF-8 are only bytes. Pure.
import Paths
import Bytes
import Ascii

Saved := [].{

	## One saved message's place, as its URL spells it: its conversation's
	## key (a DM's pair or a channel's name, matched by its text alone), its
	## topic, its id.
	Ref : {
		conv : List(U8),
		topic : List(U8),
		id : List(U8),
	}

	## parseRefs: every ref after `/chat/c/`, then every one after
	## `/channel/`. **ONE PASS PER PREFIX, NOTHING COPIED BUT THE REFS**: the
	## list is the member's whole reading list, read on every topic page.
	refs : List(U8) -> List(Ref)
	refs = |bytes| {
		# The builtin split does the scan. A ref is ASCII, and a byte
		# that is not UTF-8 becomes U+FFFD, which no ref holds.
		text = Str.from_utf8_lossy(bytes)
		List.join(
			List.map(
				["/chat/c/", "/channel/"],
				|prefix| List.keep_oks(
					List.drop_first(text.split_on(prefix), 1),
					|piece| ref_at(piece.to_utf8(), 0),
				),
			),
		)
	}

	## The ids saved in topic `topic` of conversation `conv`, in refs' order,
	## a ref saved twice twice.
	ids : List(U8), List(U8), List(U8) -> List(List(U8))
	ids = |
		text,
		conv,
		topic,
	| List.keep_oks(
		refs(text),
		|r| if r.conv == conv and r.topic == topic Ok(r.id) else Err(Elsewhere),
	)
}

## parseRefAt: `<conv>/<topic>#msg-<id>` from `start`, or nothing.
ref_at : List(U8), U64 -> Try(Saved.Ref, [NotARef])
ref_at = |text, start| {
	conv_end = Bytes.count_while(
		text,
		is_path_seg,
		start,
	)
	if conv_end == start or List.get(text, conv_end) != Ok('/') {
		Err(NotARef)
	} else {
		topic_start = conv_end + 1
		topic_end = Bytes.count_while(
			text,
			is_path_seg,
			topic_start,
		)
		anchor = "#msg-".to_utf8()
		if topic_end == topic_start or !List.starts_with(List.drop_first(text, topic_end), anchor) {
			Err(NotARef)
		} else {
			id_start = topic_end + List.len(anchor)
			id = List.sublist(
				text,
				{
					start: id_start,
					len: Bytes.count_while(
						text,
						is_id_char,
						id_start,
					) - id_start,
				},
			)
			if Paths.is_valid_msg_ref_id(id) {
				Ok({
					conv: List.sublist(text, { start, len: conv_end - start }),
					topic: List.sublist(text, { start: topic_start, len: topic_end - topic_start }),
					id,
				})
			} else {
				Err(NotARef)
			}
		}
	}
}

## A byte a conversation's key or a topic may hold in a URL (isPathSeg).
is_path_seg : U8 -> Bool
is_path_seg = |c| is_id_char(c) or c == '.'

## A byte a message's id may hold (isIdChar).
is_id_char : U8 -> Bool
is_id_char = |c| Ascii.is_alphanumeric(c) or c == '-' or c == '_'

expect Saved.ids(
	Str.to_utf8("[o](/chat/c/1_2/Plans#msg-Plans_3) /channel/1_2/Plans#msg-Plans_9 /chat/c/1_2/Plans#msg-bad /chat/c/1_2/Other#msg-Other_1"),
	Str.to_utf8("1_2"),
	Str.to_utf8("Plans"),
) == [Str.to_utf8("Plans_3"), Str.to_utf8("Plans_9")]
expect Saved.refs([]) == []
expect Saved.refs(List.concat(Str.to_utf8("/chat/c/1_2/Plans#msg-Plans_4)"), [0xff])) == [
	{
		conv: Str.to_utf8("1_2"),
		topic: Str.to_utf8("Plans"),
		id: Str.to_utf8("Plans_4"),
	},
]
