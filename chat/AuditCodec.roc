## **AN ADMIN AUDIT ENTRY, STORED** (the Roc chat's auth design, section 9):
## one line in Stored's format, appended to the audit log for every admin
## attempt, permitted or refused:
##
##     audit v1 at=1761600000 who=agent:1 via=key:4 action=revoke-keys:human:2 verdict=permitted
##     audit v1 at=1761600077 who=human:2 via=session:12 action=retire:human:1 verdict=refused:not-admin
##     audit v1 at=1761600100 who=human:1 via=session:3 action=set-role:2:admin verdict=permitted
##
## Who (a principal's id, as AccountCodec spells it), by which session or
## key (its public number, never a secret), what, when, and the verdict,
## each spelled once: an action as a word and its target after a colon (a
## role set, the human's GitHub id and the role), a refusal as a word (a
## key's refusal after `key:`). Pure.
import AccountCodec
import Admin
import ApiKey
import Bytes
import Principal
import Stored

AuditCodec := [].{

	## The entry's line.
	encode : Admin.Audit -> List(U8)
	encode = |audit|
		Stored.line(
			"audit",
			[
				("at", Stored.time_text(audit.at)),
				("who", AccountCodec.id_text(audit.who)),
				("via", via_text(audit.via)),
				("action", action_text(audit.action)),
				("verdict", verdict_text(audit.verdict)),
			],
		)

	## The entry a line holds.
	decode : List(U8) -> Try(Admin.Audit, Stored.Problem)
	decode = |raw| {
		fields = Stored.Reader.open(raw, "audit")?
		at_field = fields.field("at")?
		at = Stored.time(at_field.value, "at")?
		who_field = at_field.rest.field("who")?
		who = AccountCodec.id_from(who_field.value, "who")?
		via_field = who_field.rest.field("via")?
		via = via_from(via_field.value)?
		action_field = via_field.rest.field("action")?
		action = action_from(action_field.value)?
		verdict_field = action_field.rest.field("verdict")?
		verdict = verdict_from(verdict_field.value)?
		verdict_field.rest.close()?
		Ok({
			who,
			via,
			action,
			at,
			verdict,
		})
	}
}

Via : [Session(Principal.SessionId), Key(Principal.KeyId)]

ViaKind : [Session, Key]

all_via_kinds : List(ViaKind)
all_via_kinds = [Session, Key]

spell_via : ViaKind -> Str
spell_via = |kind|
	match kind {
		Session => "session"
		Key => "key"
	}

## `session:12` or `key:4`.
via_text : Via -> Str
via_text = |via|
	match via {
		Session(s) => "${spell_via(Session)}${colon}${s.to_u64().to_str()}"
		Key(k) => "${spell_via(Key)}${colon}${k.to_u64().to_str()}"
	}

via_from : List(U8) -> Try(Via, Stored.Problem)
via_from = |value| {
	{ head, tail } = split_colon(value, "via")?
	match Stored.word(
		head,
		{
			name: "via",
			all: all_via_kinds,
			spell: spell_via,
		},
	)? {
		Session => Stored.id(
			tail,
			{ name: "via", make: Principal.SessionId.from_u64 },
		).map_ok(|s| Session(s))
		Key => Stored.id(tail, { name: "via", make: Principal.KeyId.from_u64 }).map_ok(|k| Key(k))
	}
}

## An action's word, without its target.
ActionKind : [
	ListAccounts,
	Retire,
	RevokeKeys,
	RevokeSessions,
	SetRole,
	ReadCounters,
]

all_action_kinds : List(ActionKind)
all_action_kinds = [
	ListAccounts,
	Retire,
	RevokeKeys,
	RevokeSessions,
	SetRole,
	ReadCounters,
]

spell_action : ActionKind -> Str
spell_action = |kind|
	match kind {
		ListAccounts => "list-accounts"
		Retire => "retire"
		RevokeKeys => "revoke-keys"
		RevokeSessions => "revoke-sessions"
		SetRole => "set-role"
		ReadCounters => "read-counters"
	}

## The action's word, and its target after a colon: a principal's id, a
## human's GitHub id for their sessions, or a human's GitHub id and the
## role set, colon between.
action_text : Admin.Action -> Str
action_text = |action|
	match action {
		ListAccounts => spell_action(ListAccounts)
		Retire(id) => "${spell_action(Retire)}${colon}${AccountCodec.id_text(id)}"
		RevokeKeys(id) => "${spell_action(RevokeKeys)}${colon}${AccountCodec.id_text(id)}"
		RevokeSessions(g) => "${spell_action(RevokeSessions)}${colon}${g.to_u64().to_str()}"
		SetRole({ human, role }) => {
			target = "${human.to_u64().to_str()}${colon}${AccountCodec.role_text(role)}"
			"${spell_action(SetRole)}${colon}${target}"
		}
		ReadCounters => spell_action(ReadCounters)
	}

action_from : List(U8) -> Try(Admin.Action, Stored.Problem)
action_from = |value|
	match List.split_first(value, ':') {
		Err(NotFound) =>
			match Stored.word(
				value,
				{
					name: "action",
					all: all_action_kinds,
					spell: spell_action,
				},
			)? {
				ListAccounts => Ok(ListAccounts)
				ReadCounters => Ok(ReadCounters)
				Retire | RevokeKeys | RevokeSessions | SetRole => Err(BadValue("action"))
			}

		Ok({ before, after }) =>
			match Stored.word(
				before,
				{
					name: "action",
					all: all_action_kinds,
					spell: spell_action,
				},
			)? {
				ListAccounts | ReadCounters => Err(BadValue("action"))
				Retire => AccountCodec.id_from(after, "action").map_ok(|id| Retire(id))
				RevokeKeys => AccountCodec.id_from(after, "action").map_ok(|id| RevokeKeys(id))
				RevokeSessions =>
					Stored.id(
						after,
						{ name: "action", make: Principal.GitHubId.from_u64 },
					).map_ok(|g| RevokeSessions(g))
				SetRole => {
					{ head, tail } = split_colon(after, "action")?
					human = Stored.id(head, { name: "action", make: Principal.GitHubId.from_u64 })?
					role = AccountCodec.role_from(tail, "action")?
					Ok(SetRole({ human, role }))
				}
			}
	}

Verdict : [Permitted, Refused(Admin.Refusal)]

## The refusals Admin says itself; a key's are ApiKey's, after `key:`.
AdminRefusal : [
	NoSuchPrincipal,
	SessionExpired,
	NotAdmin,
	RetiresOwnAuthority,
	SetsOwnRole,
	NeedsSession,
]

all_admin_refusals : List(AdminRefusal)
all_admin_refusals = [
	NoSuchPrincipal,
	SessionExpired,
	NotAdmin,
	RetiresOwnAuthority,
	SetsOwnRole,
	NeedsSession,
]

spell_admin_refusal : AdminRefusal -> Str
spell_admin_refusal = |why|
	match why {
		NoSuchPrincipal => "no-such-principal"
		SessionExpired => "session-expired"
		NotAdmin => "not-admin"
		RetiresOwnAuthority => "retires-own-authority"
		SetsOwnRole => "sets-own-role"
		NeedsSession => "needs-session"
	}

all_key_refusals : List(ApiKey.Refusal)
all_key_refusals = [
	Revoked,
	Expired,
	NoSuchPrincipal,
	OutOfScope,
	BeyondPrincipal,
]

spell_key_refusal : ApiKey.Refusal -> Str
spell_key_refusal = |why|
	match why {
		Revoked => "revoked"
		Expired => "expired"
		NoSuchPrincipal => "no-such-principal"
		OutOfScope => "out-of-scope"
		BeyondPrincipal => "beyond-principal"
	}

## `permitted`, or `refused:` and the refusal (`refused:key:` and a key's).
verdict_text : Verdict -> Str
verdict_text = |verdict|
	match verdict {
		Permitted => permitted_word
		Refused(why) => "${refused_prefix}${refusal_text(why)}"
	}

## A refusal's word, a key's after `key:`.
refusal_text : Admin.Refusal -> Str
refusal_text = |why|
	match why {
		KeyRefused(key_why) => "${key_prefix}${spell_key_refusal(key_why)}"
		NoSuchPrincipal => spell_admin_refusal(NoSuchPrincipal)
		SessionExpired => spell_admin_refusal(SessionExpired)
		NotAdmin => spell_admin_refusal(NotAdmin)
		RetiresOwnAuthority => spell_admin_refusal(RetiresOwnAuthority)
		SetsOwnRole => spell_admin_refusal(SetsOwnRole)
		NeedsSession => spell_admin_refusal(NeedsSession)
	}

verdict_from : List(U8) -> Try(Verdict, Stored.Problem)
verdict_from = |value|
	if value == Str.to_utf8(permitted_word) {
		Ok(Permitted)
	} else {
		match Bytes.strip_prefix(value, Str.to_utf8(refused_prefix)) {
			Err(NoMatch) => Err(UnknownWord("verdict"))
			Ok(why) =>
				match Bytes.strip_prefix(why, Str.to_utf8(key_prefix)) {
					Ok(key_why) =>
						Stored.word(
							key_why,
							{
								name: "verdict",
								all: all_key_refusals,
								spell: spell_key_refusal,
							},
						)
							.map_ok(|w| Refused(KeyRefused(w)))

					Err(NoMatch) =>
						match Stored.word(
							why,
							{
								name: "verdict",
								all: all_admin_refusals,
								spell: spell_admin_refusal,
							},
						)? {
							NoSuchPrincipal => Ok(Refused(NoSuchPrincipal))
							SessionExpired => Ok(Refused(SessionExpired))
							NotAdmin => Ok(Refused(NotAdmin))
							RetiresOwnAuthority => Ok(Refused(RetiresOwnAuthority))
							SetsOwnRole => Ok(Refused(SetsOwnRole))
							NeedsSession => Ok(Refused(NeedsSession))
						}
				}
		}
	}

permitted_word : Str
permitted_word = "permitted"

refused_prefix : Str
refused_prefix = "refused:"

key_prefix : Str
key_prefix = "key:"

colon : Str
colon = ":"

## The bytes before and after the first colon, both there.
split_colon : List(U8), Str -> Try({ head : List(U8), tail : List(U8) }, Stored.Problem)
split_colon = |value, name|
	match List.split_first(value, ':') {
		Ok({ before, after }) => Ok({ head: before, tail: after })
		Err(NotFound) => Err(BadValue(name))
	}

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

sid : U64 -> Principal.SessionId
sid = |n|
	match Principal.SessionId.from_u64(n) {
		Ok(id) => id
		Err(NotAnId) => crash "sid: a test's session id is not 0"
	}

## An entry as text.
text_of : Admin.Audit -> Str
text_of = |audit|
	match Str.from_utf8(AuditCodec.encode(audit)) {
		Ok(text) => text
		Err(_) => crash "text_of: a stored line is UTF-8"
	}

expect
	text_of({
		who: Principal.Id.Agent(aid(1)),
		via: Key(kid(4)),
		action: RevokeKeys(Principal.Id.Human(gid(2))),
		at: 1761600000,
		verdict: Permitted,
	})
		== "audit v1 at=1761600000 who=agent:1 via=key:4 action=revoke-keys:human:2 verdict=permitted\n"
expect
	text_of({
		who: Principal.Id.Human(gid(2)),
		via: Session(sid(12)),
		action: Retire(Principal.Id.Human(gid(1))),
		at: 1761600077,
		verdict: Refused(NotAdmin),
	})
		== "audit v1 at=1761600077 who=human:2 via=session:12 action=retire:human:1 verdict=refused:not-admin\n"
expect
	text_of({
		who: Principal.Id.Bot(aid(3)),
		via: Key(kid(5)),
		action: ReadCounters,
		at: -1,
		verdict: Refused(KeyRefused(OutOfScope)),
	})
		== "audit v1 at=-1 who=bot:3 via=key:5 action=read-counters verdict=refused:key:out-of-scope\n"
expect
	text_of({
		who: Principal.Id.Human(gid(1)),
		via: Session(sid(3)),
		action: SetRole({ human: gid(2), role: Admin }),
		at: 1761600100,
		verdict: Permitted,
	})
		== "audit v1 at=1761600100 who=human:1 via=session:3 action=set-role:2:admin verdict=permitted\n"
expect
	text_of({
		who: Principal.Id.Agent(aid(1)),
		via: Key(kid(4)),
		action: SetRole({ human: gid(2), role: Member }),
		at: 1761600100,
		verdict: Refused(NeedsSession),
	})
		== "audit v1 at=1761600100 who=agent:1 via=key:4 action=set-role:2:member verdict=refused:needs-session\n"

# ── EVERY ENTRY ROUND-TRIPS: every action against every verdict, by a
# session and by a key.
actions : List(Admin.Action)
actions = [
	ListAccounts,
	Retire(Principal.Id.Human(gid(1))),
	Retire(Principal.Id.Agent(aid(2))),
	Retire(Principal.Id.Bot(aid(3))),
	RevokeKeys(Principal.Id.Human(gid(18446744073709551615))),
	RevokeKeys(Principal.Id.Agent(aid(2))),
	RevokeKeys(Principal.Id.Bot(aid(3))),
	RevokeSessions(gid(583231)),
	SetRole({ human: gid(2), role: Admin }),
	SetRole({ human: gid(583231), role: Member }),
	ReadCounters,
]

verdicts : List(Verdict)
verdicts = List.concat(
	List.concat([Permitted], List.map(all_admin_refusals, |w| when_refused(w))),
	List.map(all_key_refusals, |w| Refused(KeyRefused(w))),
)

when_refused : AdminRefusal -> Verdict
when_refused = |why|
	match why {
		NoSuchPrincipal => Refused(NoSuchPrincipal)
		SessionExpired => Refused(SessionExpired)
		NotAdmin => Refused(NotAdmin)
		RetiresOwnAuthority => Refused(RetiresOwnAuthority)
		SetsOwnRole => Refused(SetsOwnRole)
		NeedsSession => Refused(NeedsSession)
	}

entries : List(Admin.Audit)
entries =
	List.join_map(
		actions,
		|action|
			List.join_map(
				verdicts,
				|verdict| [
					{
						who: Principal.Id.Human(gid(1)),
						via: Session(sid(9)),
						action,
						at: 1761600000,
						verdict,
					},
					{
						who: Principal.Id.Agent(aid(1)),
						via: Key(kid(4)),
						action,
						at: 0,
						verdict,
					},
				],
			),
	)

expect List.len(verdicts) == 12
expect List.len(entries) == 264
expect List.all(entries, |e| AuditCodec.decode(AuditCodec.encode(e)) == Ok(e))

# ── THE MALFORMED TABLE: each line, its named problem.
usual_line : Str
usual_line = "audit v1 at=1761600000 who=agent:1 via=key:4 action=revoke-keys:human:2 verdict=permitted\n"

decoded : { from : Str, to : Str } -> Try({}, Stored.Problem)
decoded = |
	{
		from,
		to,
	},
| AuditCodec.decode(Str.to_utf8(usual_line.replace_first(from, to))).map_ok(|_| {})

expect decoded({ from: "", to: "" }) == Ok({})
expect decoded({ from: "\n", to: "" }) == Err(Torn)
expect decoded({ from: "audit", to: "audits" }) == Err(WrongRecord)
expect decoded({ from: "v1", to: "v9" }) == Err(UnknownVersion)
expect decoded({ from: "at=1761600000 ", to: "" }) == Err(MissingField("at"))
expect decoded({ from: "at=1761600000", to: "at=-0" }) == Err(BadNumber("at"))
expect decoded({ from: "who=agent:1", to: "who=agent:0" }) == Err(BadValue("who"))
expect decoded({ from: "who=agent:1", to: "who=root" }) == Err(BadValue("who"))
expect decoded({ from: "via=key:4", to: "via=cookie:4" }) == Err(UnknownWord("via"))
expect decoded({ from: "via=key:4", to: "via=key" }) == Err(BadValue("via"))
expect decoded({ from: "via=key:4", to: "via=key:0" }) == Err(BadValue("via"))
expect decoded({ from: "via=key:4", to: "via=session:x" }) == Err(BadNumber("via"))
expect decoded({ from: "via=key:4 ", to: "" }) == Err(MissingField("via"))
expect decoded({
	from: "revoke-keys:human:2",
	to: "read-mail:human:2",
}) == Err(UnknownWord("action"))
expect decoded({ from: "revoke-keys:human:2", to: "revoke-keys" }) == Err(BadValue("action"))
expect decoded({
	from: "revoke-keys:human:2",
	to: "list-accounts:human:2",
}) == Err(BadValue("action"))
expect decoded({
	from: "revoke-keys:human:2",
	to: "revoke-keys:human:0",
}) == Err(BadValue("action"))
expect decoded({
	from: "revoke-keys:human:2",
	to: "revoke-sessions:human:2",
}) == Err(BadNumber("action"))
expect decoded({ from: "revoke-keys:human:2", to: "revoke-sessions:2" }) == Ok({})
expect decoded({ from: "revoke-keys:human:2", to: "list-accounts" }) == Ok({})
expect decoded({ from: "revoke-keys:human:2", to: "set-role:2:admin" }) == Ok({})
expect decoded({ from: "revoke-keys:human:2", to: "set-role:2" }) == Err(BadValue("action"))
expect decoded({ from: "revoke-keys:human:2", to: "set-role" }) == Err(BadValue("action"))
expect decoded({ from: "revoke-keys:human:2", to: "set-role:0:admin" }) == Err(BadValue("action"))
expect decoded({
	from: "revoke-keys:human:2",
	to: "set-role:2:owner",
}) == Err(UnknownWord("action"))
expect decoded({
	from: "revoke-keys:human:2",
	to: "set-role:human:2:admin",
}) == Err(BadNumber("action"))
expect decoded({
	from: "permitted",
	to: "refused:session-not-human",
}) == Err(UnknownWord("verdict"))
expect decoded({ from: "permitted", to: "allowed" }) == Err(UnknownWord("verdict"))
expect decoded({ from: "permitted", to: "refused:" }) == Err(UnknownWord("verdict"))
expect decoded({ from: "permitted", to: "refused:not-admin" }) == Ok({})
expect decoded({ from: "permitted", to: "refused:because" }) == Err(UnknownWord("verdict"))
expect decoded({ from: "permitted", to: "refused:key:not-admin" }) == Err(UnknownWord("verdict"))
expect decoded({ from: "permitted", to: "refused:key:" }) == Err(UnknownWord("verdict"))
expect decoded({ from: " verdict=permitted", to: "" }) == Err(MissingField("verdict"))
expect decoded({ from: "permitted\n", to: "permitted by=steve\n" }) == Err(Trailing)
expect decoded({
	from: "who=agent:1 via=key:4",
	to: "via=key:4 who=agent:1",
}) == Err(MissingField("who"))
