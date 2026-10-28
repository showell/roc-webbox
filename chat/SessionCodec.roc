## **A SESSION, STORED** (the Roc chat's auth design, section 2): one line in
## Stored's format, the cookie secret's hash and never the secret:
##
##     session v1 id=12 human=583231 token=<64 hex digits> created=1761600000 seen=1761603600
##
## `decode` gives a Session through Session.load, so a record seen before it
## was created is refused (`SeenBeforeCreated`) as every other malformed
## line is, by name. Pure.
import Principal
import Session
import Stored

SessionCodec := [].{

	## The session's line.
	encode : Session -> List(U8)
	encode = |session| {
		s = session.fields()
		Stored.line(
			"session",
			[
				("id", s.id.to_u64().to_str()),
				("human", s.human.to_u64().to_str()),
				("token", Stored.hash_text(s.token_hash)),
				("created", Stored.time_text(s.created)),
				("seen", Stored.time_text(s.last_seen)),
			],
		)
	}

	## The session a line holds.
	decode : List(U8) -> Try(Session, Stored.Problem)
	decode = |raw| {
		fields = Stored.Reader.open(raw, "session")?
		id_field = fields.field("id")?
		id = Stored.id(id_field.value, { name: "id", make: Principal.SessionId.from_u64 })?
		human_field = id_field.rest.field("human")?
		human = Stored.id(human_field.value, { name: "human", make: Principal.GitHubId.from_u64 })?
		token_field = human_field.rest.field("token")?
		token_hash = Stored.hash(token_field.value, "token")?
		created_field = token_field.rest.field("created")?
		created = Stored.time(created_field.value, "created")?
		seen_field = created_field.rest.field("seen")?
		last_seen = Stored.time(seen_field.value, "seen")?
		seen_field.rest.close()?
		Session.load({
			id,
			human,
			token_hash,
			created,
			last_seen,
		}).map_err(|SeenBeforeCreated| SeenBeforeCreated)
	}
}

# ── tests

gid : U64 -> Principal.GitHubId
gid = |n|
	match Principal.GitHubId.from_u64(n) {
		Ok(id) => id
		Err(NotAnId) => crash "gid: a test's GitHub id is not 0"
	}

sid : U64 -> Principal.SessionId
sid = |n|
	match Principal.SessionId.from_u64(n) {
		Ok(id) => id
		Err(NotAnId) => crash "sid: a test's session id is not 0"
	}

## A test's token hash: every byte `b`.
token : U8 -> Stored.SecretHash
token = |b|
	match Stored.SecretHash.from_bytes(List.repeat(b, 32)) {
		Ok(h) => h
		Err(NotAHash) => crash "token: 32 bytes are a hash"
	}

## Session 12 of human 583231, created at `created` and seen at `seen`.
session_at : { created : I64, seen : I64 } -> Session
session_at = |{ created, seen }|
	match Session.load({
		id: sid(12),
		human: gid(583231),
		token_hash: token(0xab),
		created,
		last_seen: seen,
	}) {
		Ok(s) => s
		Err(SeenBeforeCreated) => crash "session_at: a test's session is seen after it was created"
	}

usual : Session
usual = session_at({ created: 1761600000, seen: 1761603600 })

ab64 : Str
ab64 = Str.repeat("ab", 32)

expect
	SessionCodec.encode(usual)
		== Str.to_utf8("session v1 id=12 human=583231 token=${ab64} created=1761600000 seen=1761603600\n")

# Round trips: the usual, a fresh one (seen when created), times at 0 and
# before 1970, the biggest ids.
expect SessionCodec.decode(SessionCodec.encode(usual)) == Ok(usual)
expect
	List.all(
		[
			session_at({ created: 5, seen: 5 }),
			session_at({ created: 0, seen: 0 }),
			session_at({ created: -100, seen: -1 }),
			session_at({ created: -9223372036854775808, seen: 9223372036854775807 }),
		],
		|s| SessionCodec.decode(SessionCodec.encode(s)) == Ok(s),
	)
biggest : Session
biggest =
	Session.start({
		id: sid(18446744073709551615),
		human: gid(18446744073709551615),
		token_hash: token(0xff),
		now: 1,
	})

expect SessionCodec.decode(SessionCodec.encode(biggest)) == Ok(biggest)

# ── THE MALFORMED TABLE: each line, its named problem.
decoded : Str -> Try({}, Stored.Problem)
decoded = |text| SessionCodec.decode(Str.to_utf8(text)).map_ok(|_| {})

## The usual line with `from` replaced by `to`.
usual_but : Str, Str -> Str
usual_but = |from, to|
	"session v1 id=12 human=583231 token=${ab64} created=1761600000 seen=1761603600\n".replace_first(from, to)

expect decoded(usual_but("", "")) == Ok({})
expect decoded(usual_but("\n", "")) == Err(Torn)
expect decoded(usual_but("\n", "\n\n")) == Err(ExtraLine)
expect decoded(usual_but("session", "account")) == Err(WrongRecord)
expect decoded(usual_but("v1", "v0")) == Err(UnknownVersion)
expect decoded(usual_but("id=12 ", "")) == Err(MissingField("id"))
expect decoded(usual_but("id=12", "id=0")) == Err(BadValue("id"))
expect decoded(usual_but("id=12", "id=012")) == Err(BadNumber("id"))
expect decoded(usual_but("human=583231 ", "")) == Err(MissingField("human"))
expect decoded(usual_but("human=583231", "human=0")) == Err(BadValue("human"))
expect decoded(usual_but("token=${ab64} ", "")) == Err(MissingField("token"))
expect decoded(usual_but(ab64, Str.repeat("AB", 32))) == Err(BadValue("token"))
expect decoded(usual_but(ab64, Str.repeat("ab", 31))) == Err(BadValue("token"))
expect decoded(usual_but(ab64, Str.repeat("ab", 33))) == Err(BadValue("token"))
expect decoded(usual_but(ab64, "")) == Err(BadValue("token"))
expect decoded(usual_but("created=1761600000 ", "")) == Err(MissingField("created"))
expect decoded(usual_but("created=1761600000", "created=1761600000.5")) == Err(BadNumber("created"))
expect decoded(usual_but(" seen=1761603600", "")) == Err(MissingField("seen"))
expect decoded(usual_but("seen=1761603600", "seen=")) == Err(BadNumber("seen"))
expect decoded(usual_but("seen=1761603600", "seen=1761599999")) == Err(SeenBeforeCreated)
expect decoded(usual_but("1761603600\n", "1761603600 \n")) == Err(Trailing)
expect decoded(usual_but("1761603600\n", "1761603600 device=x\n")) == Err(Trailing)
expect decoded(usual_but("created=1761600000 seen=1761603600", "seen=1761603600 created=1761600000")) == Err(MissingField("created"))
expect SessionCodec.decode([0xff, '\n']) == Err(NotUtf8)
