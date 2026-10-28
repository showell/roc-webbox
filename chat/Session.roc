## **A SIGN-IN SESSION, AND HOW LONG IT LIVES** (the Roc chat's auth design,
## section 2): a browser signed in as a human. The cookie carries a random
## secret; the store keeps the secret's hash (the host hashes, and looks a
## session up by it), the human, when it was created and when it was last
## seen. A record on disk rather than a signed cookie, so a session can be
## listed and ended: "log out everywhere" is real.
##
## **ITS LIFETIME, CONSERVATIVE BY DEFAULT:**
## - **idle:** a session not seen for 24 hours is over;
## - **absolute:** a session is over 7 days after it was created, however
##   often it is used, so a stolen cookie is good for a week at most;
## - a time from the future (a clock that went back) is trusted for
##   nothing: the session is over, as OAuthState's check treats a state;
## - **last seen** is written at most once in 5 minutes, so a busy browser
##   is not a write a request; idle expiry can therefore come up to 5
##   minutes early, never late.
## Only humans sign in: an agent or a bot acts through API keys. Pure.
import Principal
import Stored

Session :: {
	id : Principal.SessionId,
	human : Principal.GitHubId,
	token_hash : Stored.SecretHash,
	created : I64,
	last_seen : I64,
}.{

	## How long a session may go unseen, in seconds: 24 hours.
	idle_secs : I64
	idle_secs = 86400

	## How long a session may live at all, in seconds: 7 days.
	absolute_secs : I64
	absolute_secs = 604800

	## How stale `last seen` may be before a request writes it again, in
	## seconds: 5 minutes.
	touch_secs : I64
	touch_secs = 300

	## A session's stored fields, as SessionCodec writes and reads them.
	Fields : {
		id : Principal.SessionId,
		human : Principal.GitHubId,
		token_hash : Stored.SecretHash,
		created : I64,
		last_seen : I64,
	}

	## What a session is at a time.
	Liveness : [
		Live,
		IdleExpired,
		AbsoluteExpired,
	]

	## **A NEW SESSION**, created and seen `now`: the sign-in flow's end.
	start : {
		id : Principal.SessionId,
		human : Principal.GitHubId,
		token_hash : Stored.SecretHash,
		now : I64,
	} -> Session
	start = |{ id, human, token_hash, now }|
		Session.(
			{
				id,
				human,
				token_hash,
				created: now,
				last_seen: now,
			},
		)

	## **A SESSION AS ITS STORED RECORD HOLDS IT**, when the record could
	## be one: seen no earlier than it was created.
	load : Session.Fields -> Try(Session, [SeenBeforeCreated])
	load = |fields| if fields.last_seen < fields.created Err(SeenBeforeCreated) else Ok(Session.(fields))

	## The session's fields, to store.
	fields : Session -> Session.Fields
	fields = |Session.(s)| s

	## The session's public number.
	id : Session -> Principal.SessionId
	id = |Session.(s)| s.id

	## The human signed in.
	human : Session -> Principal.GitHubId
	human = |Session.(s)| s.human

	## **IS THE SESSION LIVE AT `now`?** The absolute limit is said first:
	## a session past both is `AbsoluteExpired`. A creation or a last
	## sight after `now` is `AbsoluteExpired` too: nothing is trusted from
	## a time not yet reached. Each limit is live before it and over from
	## it on.
	liveness : Session, I64 -> Session.Liveness
	liveness = |Session.(s), now| {
		age = now - s.created
		unseen = now - s.last_seen
		if age < 0 or unseen < 0 or age >= Session.absolute_secs {
			AbsoluteExpired
		} else if unseen >= Session.idle_secs {
			IdleExpired
		} else {
			Live
		}
	}

	## **A REQUEST ON THIS SESSION, AT `now`**: admitted as its human, as
	## the accounts say now, when it is live and the human still has an
	## account (one retired takes their sessions with them); with the
	## session to write back when `last seen` is `touch_secs` stale or
	## more.
	admit : Session,
	{
		accounts : List(Principal),
		now : I64,
	} -> [
		Admitted({ principal : Principal, write : [Unchanged, Touched(Session)] }),
		Refused([IdleExpired, AbsoluteExpired, NoSuchAccount]),
	]
	admit = |session, { accounts, now }| {
		Session.(s) = session
		match session.liveness(now) {
			IdleExpired => Refused(IdleExpired)
			AbsoluteExpired => Refused(AbsoluteExpired)
			Live =>
				match Principal.find(accounts, Principal.Id.Human(s.human)) {
					Err(NoSuchPrincipal) => Refused(NoSuchAccount)
					Ok(principal) => {
						write = if now - s.last_seen >= Session.touch_secs Touched(Session.({ ..s, last_seen: now })) else Unchanged
						Admitted({ principal, write })
					}
				}
		}
	}

	## **LOG OUT EVERYWHERE**: of `sessions`, every one of `human`'s, the
	## one asking included, live or not; nobody else's.
	log_out_everywhere : List(Session), Principal.GitHubId -> List(Principal.SessionId)
	log_out_everywhere = |sessions, whose|
		List.keep_if(sessions, |s| s.human() == whose).map(Session.id)

	## **THE SWEEP**: of `sessions`, every one over at `now`, for the host
	## to delete.
	sweep : List(Session), I64 -> List(Principal.SessionId)
	sweep = |sessions, now|
		List.keep_if(sessions, |s| s.liveness(now) != Live).map(Session.id)

	is_eq : _
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

## Session `n` of human `who`, created at `at`.
opened : { n : U64, who : U64, at : I64 } -> Session
opened = |{ n, who, at }|
	Session.start({
		id: sid(n),
		human: gid(who),
		token_hash: token(1),
		now: at,
	})

# Created at 1000.
s1 : Session
s1 = opened({ n: 1, who: 1, at: 1000 })

day : I64
day = Session.idle_secs

week : I64
week = Session.absolute_secs

# ── THE LIVENESS TABLE
# Fresh, at each limit's edge, past both, and from the future.
expect s1.liveness(1000) == Live
expect s1.liveness(1000 + day - 1) == Live
expect s1.liveness(1000 + day) == IdleExpired
expect s1.liveness(1000 + week) == AbsoluteExpired
expect s1.liveness(999) == AbsoluteExpired

## `s1`, last seen at `at`.
seen_at : I64 -> Session
seen_at = |at|
	match Session.load({ ..s1.fields(), last_seen: at }) {
		Ok(s) => s
		Err(SeenBeforeCreated) => crash "seen_at: a test's session is seen after it was created"
	}

# Used every day, it lives a week and not a second more.
expect seen_at(1000 + week - 10).liveness(1000 + week - 1) == Live
expect seen_at(1000 + week - 10).liveness(1000 + week) == AbsoluteExpired

# Idle a day from its last sight, not from its creation.
expect seen_at(5000).liveness(5000 + day - 1) == Live
expect seen_at(5000).liveness(5000 + day) == IdleExpired

# Seen in the future: over.
expect seen_at(5000).liveness(4999) == AbsoluteExpired

# Loading: never seen before created.
expect Session.load({ ..s1.fields(), last_seen: 999 }) == Err(SeenBeforeCreated)
expect Session.load(s1.fields()) == Ok(s1)

# ── ADMITTING A REQUEST
ann : Principal
ann = Principal.Human({ id: gid(1), login: "ann", name: "Ann", role: Member })

bea : Principal
bea = Principal.Human({ id: gid(2), login: "bea", name: "Bea", role: Member })

Admission : [Admitted({ principal : Principal.Id, write : [Unchanged, Touched(I64)] }), Refused([IdleExpired, AbsoluteExpired, NoSuchAccount])]

## The admission of `session` at `now` among `among`, the principal by id
## and a write by the last sight it writes.
admitted : Session, { among : List(Principal), now : I64 } -> Admission
admitted = |session, { among, now }|
	match session.admit({ accounts: among, now }) {
		Refused(why) => Refused(why)
		Admitted({ principal, write }) =>
			Admitted({
				principal: Principal.id(principal),
				write: match write {
					Unchanged => Unchanged
					Touched(s) => Touched(s.fields().last_seen)
				},
			})
	}

expect admitted(s1, { among: [ann, bea], now: 1000 }) == Admitted({ principal: Principal.id(ann), write: Unchanged })
expect admitted(s1, { among: [ann, bea], now: 1299 }) == Admitted({ principal: Principal.id(ann), write: Unchanged })
expect admitted(s1, { among: [ann, bea], now: 1300 }) == Admitted({ principal: Principal.id(ann), write: Touched(1300) })
expect admitted(s1, { among: [ann, bea], now: 1000 + day }) == Refused(IdleExpired)
expect admitted(seen_at(1000 + week - 1), { among: [ann], now: 1000 + week }) == Refused(AbsoluteExpired)
expect admitted(s1, { among: [ann], now: 999 }) == Refused(AbsoluteExpired)

# Ann retired: her live session admits nobody.
expect admitted(s1, { among: [bea], now: 1000 }) == Refused(NoSuchAccount)

# The role is the accounts' now, not the one at sign-in.
expect
	match s1.admit({ accounts: [Principal.Human({ id: gid(1), login: "ann", name: "Ann", role: Admin })], now: 1000 }) {
		Admitted({ principal: Human(h), write: _ }) => h.role == Admin
		_ => Bool.False
	}

# ── LOG OUT EVERYWHERE, AND THE SWEEP
# Ann's sessions 1 and 2 (2 a day older, idle by 1000), Bea's 3.
sessions : List(Session)
sessions = [
	s1,
	opened({ n: 2, who: 1, at: 1000 - day }),
	opened({ n: 3, who: 2, at: 1000 }),
]

expect Session.log_out_everywhere(sessions, gid(1)) == [sid(1), sid(2)]
expect Session.log_out_everywhere(sessions, gid(2)) == [sid(3)]
expect Session.log_out_everywhere(sessions, gid(9)) == []
expect Session.log_out_everywhere([], gid(1)) == []
expect Session.sweep(sessions, 1000) == [sid(2)]
expect Session.sweep(sessions, 1000 + day - 1) == [sid(2)]
expect Session.sweep(sessions, 1000 + day) == [sid(1), sid(2), sid(3)]
expect Session.sweep(sessions, 999) == [sid(1), sid(3)]
expect Session.sweep([], 1000) == []
