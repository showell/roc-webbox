## **AN API KEY, STORED** (the Roc chat's auth design, sections 3 and 9):
## one line in Stored's format, the key's hash and never the key, which its
## owner is shown once:
##
##     key v1 id=4 acts=agent:7 hash=<64 hex digits> created=1761600000 expires=never state=active read=only:3,9 post=off admin=off
##
## The chat's keys, over its conversations (ConvAccess.ConvId). `decode` is
## the store's way back to an ApiKey.Key, through `ApiKey.Key.load`, which
## takes the record's scope exactly: a read or a post reach `off`,
## `everywhere`, or `only:` its conversations; admin `off` or `on`; nothing
## is widened or defaulted. A key acting as a bot with admin on is refused
## (`AdminForBot`): no grant makes one (a bot is never an admin), so the
## record is not one the chat wrote. Pure.
import AccountCodec
import ApiKey
import Bytes
import ConvAccess
import Principal
import Stored

KeyCodec := [].{

	## The chat's key, over its conversations.
	Key : ApiKey.Key(ConvAccess.ConvId)

	## **WHAT THE STORE KEEPS OF A KEY**: the key, the hash the host looks
	## it up by, and when it was made.
	Entry : {
		key : KeyCodec.Key,
		hash : Stored.SecretHash,
		created : I64,
	}

	## The entry's line.
	encode : KeyCodec.Entry -> List(U8)
	encode = |
		{
			key,
			hash,
			created,
		},
	| {
		k = key.record()
		Stored.line(
			"key",
			[
				("id", k.id.to_u64().to_str()),
				("acts", AccountCodec.id_text(k.acts_as)),
				("hash", Stored.hash_text(hash)),
				("created", Stored.time_text(created)),
				("expires", expiry_text(k.expires)),
				("state", spell_revocation(k.revocation)),
				("read", reach_text(k.scope.read)),
				("post", reach_text(k.scope.post)),
				("admin", spell_switch(k.scope.admin)),
			],
		)
	}

	## The entry a line holds.
	decode : List(U8) -> Try(KeyCodec.Entry, Stored.Problem)
	decode = |raw| {
		fields = Stored.Reader.open(raw, "key")?
		id_field = fields.field("id")?
		id = Stored.id(id_field.value, { name: "id", make: Principal.KeyId.from_u64 })?
		acts_field = id_field.rest.field("acts")?
		acts_as = AccountCodec.id_from(acts_field.value, "acts")?
		hash_field = acts_field.rest.field("hash")?
		hash = Stored.hash(hash_field.value, "hash")?
		created_field = hash_field.rest.field("created")?
		created = Stored.time(created_field.value, "created")?
		expires_field = created_field.rest.field("expires")?
		expires = expiry_from(expires_field.value)?
		state_field = expires_field.rest.field("state")?
		revocation = Stored.word(
			state_field.value,
			{
				name: "state",
				all: all_revocations,
				spell: spell_revocation,
			},
		)?
		read_field = state_field.rest.field("read")?
		read = reach_from(read_field.value, "read")?
		post_field = read_field.rest.field("post")?
		post = reach_from(post_field.value, "post")?
		admin_field = post_field.rest.field("admin")?
		admin = Stored.word(
			admin_field.value,
			{
				name: "admin",
				all: all_switches,
				spell: spell_switch,
			},
		)?
		admin_field.rest.close()?
		match (acts_as, admin) {
			(Bot(_), On) => Err(AdminForBot)
			_ =>
				Ok({
					key: ApiKey.Key.load({
						id,
						acts_as,
						scope: {
							read,
							post,
							admin,
						},
						expires,
						revocation,
					}),
					hash,
					created,
				})
		}
	}
}

Revocation : [Active, Revoked]

all_revocations : List(Revocation)
all_revocations = [Active, Revoked]

spell_revocation : Revocation -> Str
spell_revocation = |r|
	match r {
		Active => "active"
		Revoked => "revoked"
	}

Switch : [Off, On]

all_switches : List(Switch)
all_switches = [Off, On]

spell_switch : Switch -> Str
spell_switch = |s|
	match s {
		Off => "off"
		On => "on"
	}

## `never`, or `at:` and the time.
expiry_text : ApiKey.Expiry -> Str
expiry_text = |expiry|
	match expiry {
		Never => never_word
		At(t) => "${at_prefix}${Stored.time_text(t)}"
	}

expiry_from : List(U8) -> Try(ApiKey.Expiry, Stored.Problem)
expiry_from = |value|
	if value == Str.to_utf8(never_word) {
		Ok(Never)
	} else {
		match Bytes.strip_prefix(value, Str.to_utf8(at_prefix)) {
			Ok(time) => Stored.time(time, "expires").map_ok(|t| At(t))
			Err(NoMatch) => Err(UnknownWord("expires"))
		}
	}

never_word : Str
never_word = "never"

at_prefix : Str
at_prefix = "at:"

ReachPart : [Off, On(ApiKey.Reach(ConvAccess.ConvId))]

## `off`, `everywhere`, or `only:` and the conversations, commas between.
reach_text : ReachPart -> Str
reach_text = |part|
	match part {
		Off => spell_switch(Off)
		On(Everywhere) => everywhere_word
		On(Only(convs)) => {
			listed = List.map(convs, |c| c.to_u64().to_str())
			"${only_prefix}${Str.join_with(listed, ",")}"
		}
	}

reach_from : List(U8), Str -> Try(ReachPart, Stored.Problem)
reach_from = |value, name|
	if value == Str.to_utf8(spell_switch(Off)) {
		Ok(Off)
	} else if value == Str.to_utf8(everywhere_word) {
		Ok(On(Everywhere))
	} else {
		match Bytes.strip_prefix(value, Str.to_utf8(only_prefix)) {
			Err(NoMatch) => Err(UnknownWord(name))
			Ok([]) => Ok(On(Only([])))
			Ok(listed) => {
				convs = List.map_try(
					List.split_on(listed, ','),
					|c| Stored.id(c, { name, make: ConvAccess.ConvId.from_u64 }),
				)?
				Ok(On(Only(convs)))
			}
		}
	}

everywhere_word : Str
everywhere_word = "everywhere"

only_prefix : Str
only_prefix = "only:"

# ── tests

gid : U64 -> Principal.GitHubId
gid = |n|
	match Principal.GitHubId.from_u64(n) {
		Ok(id) => id
		Err(NotAnId) => crash "gid: a test's GitHub id is not 0"
	}

aid : U64 -> Principal.AgentId
aid = |n|
	match Principal.AgentId.from_u64(n) {
		Ok(id) => id
		Err(NotAnId) => crash "aid: a test's agent id is not 0"
	}

kid : U64 -> Principal.KeyId
kid = |n|
	match Principal.KeyId.from_u64(n) {
		Ok(id) => id
		Err(NotAnId) => crash "kid: a test's key id is not 0"
	}

conv : U64 -> ConvAccess.ConvId
conv = |n|
	match ConvAccess.ConvId.from_u64(n) {
		Ok(id) => id
		Err(NotAnId) => crash "conv: a test's conversation id is not 0"
	}

## A test's hash: every byte `b`.
hash_of : U8 -> Stored.SecretHash
hash_of = |b|
	match Stored.SecretHash.from_bytes(List.repeat(b, 32)) {
		Ok(h) => h
		Err(NotAHash) => crash "hash_of: 32 bytes are a hash"
	}

## An entry for the record `r`, made at 1761600000.
entry : ApiKey.Record(ConvAccess.ConvId) -> KeyCodec.Entry
entry = |r| {
	key: ApiKey.Key.load(r),
	hash: hash_of(0x5a),
	created: 1761600000,
}

## A commit bot's key: agent 7, reading and posting #3 and #9 alone.
narrow : ApiKey.Record(ConvAccess.ConvId)
narrow = {
	id: kid(4),
	acts_as: Principal.Id.Agent(aid(7)),
	scope: {
		read: On(Only([conv(3), conv(9)])),
		post: Off,
		admin: Off,
	},
	expires: Never,
	revocation: Active,
}

## Every part of a record at its other value: a human's, everywhere, admin,
## expiring, revoked.
broad : ApiKey.Record(ConvAccess.ConvId)
broad = {
	id: kid(18446744073709551615),
	acts_as: Principal.Id.Human(gid(583231)),
	scope: {
		read: On(Everywhere),
		post: On(Only([])),
		admin: On,
	},
	expires: At(1761609999),
	revocation: Revoked,
}

## What a test compares of an entry: Key has no `==`, its record does.
Seen : {
	record : ApiKey.Record(ConvAccess.ConvId),
	hash : Stored.SecretHash,
	created : I64,
}

seen : KeyCodec.Entry -> Seen
seen = |e| {
	record: e.key.record(),
	hash: e.hash,
	created: e.created,
}

## The entry survives a round trip whole.
is_kept : KeyCodec.Entry -> Bool
is_kept = |e| KeyCodec.decode(KeyCodec.encode(e)).map_ok(seen) == Ok(seen(e))

hex5a : Str
hex5a = Str.repeat("5a", 32)

narrow_line : Str
narrow_line = "key v1 id=4 acts=agent:7 hash=${hex5a} created=1761600000 expires=never state=active read=only:3,9 post=off admin=off\n"

expect KeyCodec.encode(entry(narrow)) == Str.to_utf8(narrow_line)
expect
	KeyCodec.encode(entry(broad))
		== Str.to_utf8("key v1 id=18446744073709551615 acts=human:583231 hash=${hex5a} created=1761600000 expires=at:1761609999 state=revoked read=everywhere post=only: admin=on\n")

# Round trips: every part at each of its values.
expect is_kept(entry(narrow))
expect is_kept(entry(broad))
expect
	List.all(
		[
			{ ..narrow, acts_as: Principal.Id.Bot(aid(2)) },
			{ ..narrow, expires: At(-1) },
			{ ..narrow, expires: At(0) },
			{
				..narrow,
				scope: {
					read: Off,
					post: On(Everywhere),
					admin: Off,
				},
			},
			{
				..narrow,
				scope: {
					read: On(Only([conv(5)])),
					post: On(Only([conv(5), conv(5)])),
					admin: Off,
				},
			},
			{ ..broad, revocation: Active },
		],
		|r| is_kept(entry(r)),
	)

# **THE SCOPE IS THE RECORD'S, EXACTLY**: the narrow key decodes narrow;
# its admin stays off; a reach of `only:` reaches nothing.
narrow_scope : Try(ApiKey.Scope(ConvAccess.ConvId), Stored.Problem)
narrow_scope = KeyCodec.decode(Str.to_utf8(narrow_line)).map_ok(|e| e.key.record().scope)

expect narrow_scope == Ok(narrow.scope)
expect
	KeyCodec.decode(Str.to_utf8(narrow_line.replace_first("read=only:3,9", "read=only:")))
		.map_ok(|e| e.key.record().scope.read)
		== Ok(On(Only([])))

# ── THE MALFORMED TABLE: each line, its named problem.
decoded : Str -> Try({}, Stored.Problem)
decoded = |text| KeyCodec.decode(Str.to_utf8(text)).map_ok(|_| {})

## The narrow line with `from` replaced by `to`.
narrow_but : { from : Str, to : Str } -> Str
narrow_but = |{ from, to }| narrow_line.replace_first(from, to)

expect decoded(narrow_but({ from: "\n", to: "" })) == Err(Torn)
expect decoded(narrow_but({ from: "key v1", to: "key v2" })) == Err(UnknownVersion)
expect decoded(narrow_but({ from: "key v1", to: "keys v1" })) == Err(WrongRecord)
expect decoded(narrow_but({ from: "id=4", to: "id=0" })) == Err(BadValue("id"))
expect decoded(narrow_but({ from: "id=4 ", to: "" })) == Err(MissingField("id"))
expect decoded(narrow_but({ from: "acts=agent:7", to: "acts=agent:0" })) == Err(BadValue("acts"))
expect decoded(narrow_but({ from: "acts=agent:7", to: "acts=agent7" })) == Err(BadValue("acts"))
expect decoded(narrow_but({ from: "acts=agent:7", to: "acts=admin:7" })) == Err(UnknownWord("acts"))
expect decoded(narrow_but({ from: "hash=", to: "hash=0" })) == Err(BadValue("hash"))
expect decoded(narrow_but({ from: hex5a, to: Str.repeat("5A", 32) })) == Err(BadValue("hash"))
expect decoded(narrow_but({ from: "hash=${hex5a} ", to: "" })) == Err(MissingField("hash"))
expect decoded(
	narrow_but({
		from: "created=1761600000",
		to: "created=now",
	}),
) == Err(BadNumber("created"))
expect decoded(
	narrow_but({
		from: "expires=never",
		to: "expires=Never",
	}),
) == Err(UnknownWord("expires"))
expect decoded(narrow_but({ from: "expires=never", to: "expires=" })) == Err(UnknownWord("expires"))
expect decoded(
	narrow_but({
		from: "expires=never",
		to: "expires=at:",
	}),
) == Err(BadNumber("expires"))
expect decoded(
	narrow_but({
		from: "expires=never",
		to: "expires=at:017",
	}),
) == Err(BadNumber("expires"))
expect decoded(
	narrow_but({
		from: "expires=never",
		to: "expires=1761609999",
	}),
) == Err(UnknownWord("expires"))
expect decoded(narrow_but({ from: "state=active", to: "state=live" })) == Err(UnknownWord("state"))
expect decoded(narrow_but({ from: "state=active ", to: "" })) == Err(MissingField("state"))
expect decoded(narrow_but({ from: "read=only:3,9", to: "read=all" })) == Err(UnknownWord("read"))
expect decoded(narrow_but({ from: "read=only:3,9", to: "read=" })) == Err(UnknownWord("read"))
expect decoded(
	narrow_but({
		from: "read=only:3,9",
		to: "read=only:3,,9",
	}),
) == Err(BadNumber("read"))
expect decoded(
	narrow_but({
		from: "read=only:3,9",
		to: "read=only:3,9,",
	}),
) == Err(BadNumber("read"))
expect decoded(narrow_but({ from: "read=only:3,9", to: "read=only:3,0" })) == Err(BadValue("read"))
expect decoded(narrow_but({ from: "read=only:3,9", to: "read=only:3;9" })) == Err(BadNumber("read"))
expect decoded(narrow_but({ from: "post=off", to: "post=on" })) == Err(UnknownWord("post"))
expect decoded(narrow_but({ from: "post=off ", to: "" })) == Err(MissingField("post"))
expect decoded(narrow_but({ from: "admin=off", to: "admin=yes" })) == Err(UnknownWord("admin"))
expect decoded(narrow_but({ from: " admin=off", to: "" })) == Err(MissingField("admin"))
expect decoded(narrow_but({ from: "admin=off\n", to: "admin=off \n" })) == Err(Trailing)
expect decoded(narrow_but({ from: "admin=off\n", to: "admin=off last_used=1\n" })) == Err(Trailing)
expect decoded(
	narrow_but({
		from: "read=only:3,9 post=off",
		to: "post=off read=only:3,9",
	}),
) == Err(MissingField("read"))

# A bot with admin on: no grant makes one.
expect decoded(narrow_but({ from: "acts=agent:7", to: "acts=bot:7" })) == Ok({})
expect
	decoded(
		narrow_but({
			from: "acts=agent:7",
			to: "acts=bot:7",
		}).replace_first("admin=off", "admin=on"),
	)
		== Err(AdminForBot)
expect decoded(narrow_but({ from: "admin=off", to: "admin=on" })) == Ok({})
