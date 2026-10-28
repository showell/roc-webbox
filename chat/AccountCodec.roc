## **AN ACCOUNT, STORED** (the Roc chat's auth design, section 1): a human,
## an agent or a bot, one line in Stored's format:
##
##     account v1 kind=human github=583231 login=octocat role=admin name=Steve H.
##     account v1 kind=agent id=7 owner=583231 name=CC
##     account v1 kind=bot id=9 owner=583231 name=commits
##
## A human is keyed by its GitHub id; an agent and a bot by the chat's own
## id, with the GitHub id of the human who owns it. The name is last, as
## Stored's free text is, and held to DisplayName's rule both ways; a login
## to GitHubLogin's. `decode` gives a Principal or a named Stored.Problem,
## never a guess. Pure.
import DisplayName
import GitHubLogin
import Principal
import Stored

AccountCodec := [].{

	## Why an account will not encode: a name or a login its rule refuses
	## (an account built by hand; the sign-in flow makes only good ones).
	## Stored as it is, it would not decode.
	EncodeProblem : [
		NameRefused(DisplayName.Problem),
		NameUntrimmed,
		LoginRefused,
	]

	## The account's line.
	encode : Principal -> Try(List(U8), AccountCodec.EncodeProblem)
	encode = |principal|
		match principal {
			Human(h) => {
				name = name_text(h.name)?
				login = GitHubLogin.from_str(h.login).map_err(|_| LoginRefused)?
				Ok(
					Stored.line(
						"account",
						[
							("kind", spell_kind(Human)),
							("github", h.id.to_u64().to_str()),
							("login", login.to_str()),
							("role", spell_role(h.role)),
							("name", name),
						],
					),
				)
			}

			Agent(a) => owned_line(Agent, { id: a.id, owner: a.owner, name: a.name })
			Bot(b) => owned_line(Bot, { id: b.id, owner: b.owner, name: b.name })
		}

	## The account a line holds.
	decode : List(U8) -> Try(Principal, Stored.Problem)
	decode = |raw| {
		fields = Stored.Reader.open(raw, "account")?
		kind = fields.field("kind")?
		match Stored.word(kind.value, { name: "kind", all: all_kinds, spell: spell_kind })? {
			Human => decode_human(kind.rest)
			Agent => decode_owned(kind.rest).map_ok(|a| Principal.Agent(a))
			Bot => decode_owned(kind.rest).map_ok(|b| Principal.Bot(b))
		}
	}
}

Kind : [Human, Agent, Bot]

all_kinds : List(Kind)
all_kinds = [Human, Agent, Bot]

spell_kind : Kind -> Str
spell_kind = |kind|
	match kind {
		Human => "human"
		Agent => "agent"
		Bot => "bot"
	}

all_roles : List(Principal.Role)
all_roles = [Admin, Member]

spell_role : Principal.Role -> Str
spell_role = |role|
	match role {
		Admin => "admin"
		Member => "member"
	}

## The name as stored: it passes the rule and is already trimmed.
name_text : Str -> Try(Str, AccountCodec.EncodeProblem)
name_text = |name|
	match DisplayName.from_str(name) {
		Err(why) => Err(NameRefused(why))
		Ok(taken) => if taken.to_str() == name Ok(name) else Err(NameUntrimmed)
	}

## An agent's or a bot's line.
owned_line : [Agent, Bot],
{
	id : Principal.AgentId,
	owner : Principal.GitHubId,
	name : Str,
} -> Try(List(U8), AccountCodec.EncodeProblem)
owned_line = |kind, { id, owner, name }| {
	text = name_text(name)?
	Ok(
		Stored.line(
			"account",
			[
				(
					"kind",
					match kind {
						Agent => spell_kind(Agent)
						Bot => spell_kind(Bot)
					},
				),
				("id", id.to_u64().to_str()),
				("owner", owner.to_u64().to_str()),
				("name", text),
			],
		),
	)
}

## A human's fields, after its kind.
decode_human : Stored.Reader -> Try(Principal, Stored.Problem)
decode_human = |after_kind| {
	github = after_kind.field("github")?
	id = Stored.id(github.value, { name: "github", make: Principal.GitHubId.from_u64 })?
	login = github.rest.field("login")?
	login_text = GitHubLogin.from_utf8(login.value).map_err(|_| BadValue("login"))?
	role = login.rest.field("role")?
	role_word = Stored.word(role.value, { name: "role", all: all_roles, spell: spell_role })?
	name = stored_name(role.rest)?
	Ok(
		Principal.Human({
			id,
			login: login_text.to_str(),
			name,
			role: role_word,
		}),
	)
}

## An agent's or a bot's fields, after its kind.
decode_owned : Stored.Reader -> Try(
	{
		id : Principal.AgentId,
		name : Str,
		owner : Principal.GitHubId,
	},
	Stored.Problem,
)
decode_owned = |after_kind| {
	id_field = after_kind.field("id")?
	id = Stored.id(id_field.value, { name: "id", make: Principal.AgentId.from_u64 })?
	owner_field = id_field.rest.field("owner")?
	owner = Stored.id(owner_field.value, { name: "owner", make: Principal.GitHubId.from_u64 })?
	name = stored_name(owner_field.rest)?
	Ok({ id, name, owner })
}

## The last field, the name: as the rule takes it, already trimmed.
stored_name : Stored.Reader -> Try(Str, Stored.Problem)
stored_name = |fields| {
	text = fields.text("name")?
	match name_text(text) {
		Ok(name) => Ok(name)
		Err(_) => Err(BadValue("name"))
	}
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

## A test's human, its name and role.
human : { name : Str, role : Principal.Role } -> Principal
human = |{ name, role }|
	Principal.Human({
		id: gid(583231),
		login: "octocat",
		name,
		role,
	})

steve : Principal
steve = human({ name: "Steve H.", role: Admin })

cc : Principal
cc = Principal.Agent({ id: aid(7), owner: gid(583231), name: "CC" })

commits : Principal
commits = Principal.Bot({ id: aid(9), owner: gid(583231), name: "commits" })

## **A PRINCIPAL, EVERY FIELD OF IT, FOR A TEST TO COMPARE**: Principal has
## no `==` on purpose (two principals are the same one when their ids are),
## and a round trip must keep every field, not only the id.
Every : [
	Human({ id : Principal.GitHubId, login : Str, name : Str, role : Principal.Role }),
	Agent({ id : Principal.AgentId, name : Str, owner : Principal.GitHubId }),
	Bot({ id : Principal.AgentId, name : Str, owner : Principal.GitHubId }),
]

every : Principal -> Every
every = |principal|
	match principal {
		Human(h) => Human(h)
		Agent(a) => Agent(a)
		Bot(b) => Bot(b)
	}

## The account, stored and read back.
round_trip : Principal -> Try(Every, [Encode(AccountCodec.EncodeProblem), Decode(Stored.Problem)])
round_trip = |account| {
	line = AccountCodec.encode(account).map_err(|why| Encode(why))?
	AccountCodec.decode(line).map_err(|why| Decode(why)).map_ok(every)
}

## The account survives a round trip whole.
is_kept : Principal -> Bool
is_kept = |account| round_trip(account) == Ok(every(account))

## The account's line, as text.
line_of : Principal -> Str
line_of = |account|
	match AccountCodec.encode(account) {
		Ok(bytes) =>
			match Str.from_utf8(bytes) {
				Ok(text) => text
				Err(_) => crash "line_of: a stored line is UTF-8"
			}
		Err(_) => crash "line_of: a test's account encodes"
	}

# The exact lines.
expect line_of(steve) == "account v1 kind=human github=583231 login=octocat role=admin name=Steve H.\n"
expect line_of(cc) == "account v1 kind=agent id=7 owner=583231 name=CC\n"
expect line_of(commits) == "account v1 kind=bot id=9 owner=583231 name=commits\n"

# Round trips: every kind, every role, names that look like fields, a
# non-ASCII name, the longest id.
expect is_kept(steve)
expect is_kept(human({ name: "Ann", role: Member }))
expect is_kept(cc)
expect is_kept(commits)
expect
	List.all(
		[
			"x role=admin",
			"name=root",
			"Zoë 🦊",
			"a  b",
			"=",
		],
		|name| is_kept(human({ name, role: Member })),
	)
biggest : Principal
biggest = Principal.Bot({ id: aid(18446744073709551615), owner: gid(18446744073709551615), name: "max" })

expect is_kept(biggest)
expect round_trip(steve) != round_trip(human({ name: "Steve H.", role: Member }))

# Bytes round trip too: a decoded line encodes to the same bytes.
expect
	List.all(
		[
			"account v1 kind=human github=1 login=a role=member name=b\n",
			"account v1 kind=agent id=7 owner=583231 name=CC\n",
			"account v1 kind=bot id=9 owner=2 name=commits bot\n",
		],
		|text| {
			raw = Str.to_utf8(text)
			match AccountCodec.decode(raw) {
				Ok(account) => AccountCodec.encode(account) == Ok(raw)
				Err(_) => Bool.False
			}
		},
	)

# ── THE MALFORMED TABLE: each line, its named problem.
decoded : Str -> Try({}, Stored.Problem)
decoded = |text| AccountCodec.decode(Str.to_utf8(text)).map_ok(|_| {})

expect decoded("") == Err(Torn)
expect decoded("account v1 kind=agent id=7 owner=5 name=CC") == Err(Torn)
expect decoded("account v1 kind=agent id=7 owner=5 name=CC\naccount v1 kind=agent id=8 owner=5 name=CD\n") == Err(ExtraLine)
expect decoded("session v1 id=1\n") == Err(WrongRecord)
expect decoded("account v2 kind=agent id=7 owner=5 name=CC\n") == Err(UnknownVersion)
expect decoded("account v1 kind=robot id=7 owner=5 name=CC\n") == Err(UnknownWord("kind"))
expect decoded("account v1 kind=Human github=1 login=a role=member name=b\n") == Err(UnknownWord("kind"))
expect decoded("account v1 github=1 login=a role=member name=b\n") == Err(MissingField("kind"))
expect decoded("account v1 kind=human login=a github=1 role=member name=b\n") == Err(MissingField("github"))
expect decoded("account v1 kind=human github=1 role=member name=b\n") == Err(MissingField("login"))
expect decoded("account v1 kind=human github=1 github=1 login=a role=member name=b\n") == Err(MissingField("login"))
expect decoded("account v1 kind=human github=1 login=a name=b\n") == Err(MissingField("role"))
expect decoded("account v1 kind=human github=1 login=a role=member\n") == Err(MissingField("name"))
expect decoded("account v1 kind=human github=1 login=a  role=member name=b\n") == Err(MissingField("role"))
expect decoded("account v1 kind=human github=1 login=a extra=1 role=member name=b\n") == Err(MissingField("role"))
expect decoded("account v1 kind=human github=0 login=a role=member name=b\n") == Err(BadValue("github"))
expect decoded("account v1 kind=human github=01 login=a role=member name=b\n") == Err(BadNumber("github"))
expect decoded("account v1 kind=human github=-1 login=a role=member name=b\n") == Err(BadNumber("github"))
expect decoded("account v1 kind=human github= login=a role=member name=b\n") == Err(BadNumber("github"))
expect decoded("account v1 kind=human github=1 login=a_b role=member name=b\n") == Err(BadValue("login"))
expect decoded("account v1 kind=human github=1 login= role=member name=b\n") == Err(BadValue("login"))
expect decoded("account v1 kind=human github=1 login=a role=owner name=b\n") == Err(UnknownWord("role"))
expect decoded("account v1 kind=human github=1 login=a role=Admin name=b\n") == Err(UnknownWord("role"))
expect decoded("account v1 kind=human github=1 login=a role=member name=\n") == Err(BadValue("name"))
expect decoded("account v1 kind=human github=1 login=a role=member name= b\n") == Err(BadValue("name"))
expect decoded("account v1 kind=human github=1 login=a role=member name=b \n") == Err(BadValue("name"))
expect decoded("account v1 kind=human github=1 login=a role=member name=b\r\n") == Err(BadValue("name"))
expect decoded("account v1 kind=human github=1 login=a role=member name=a\tb\n") == Err(BadValue("name"))
expect decoded("account v1 kind=human github=1 login=a role=member name=${Str.repeat("n", 65)}\n") == Err(BadValue("name"))
expect decoded("account v1 kind=agent id=0 owner=5 name=CC\n") == Err(BadValue("id"))
expect decoded("account v1 kind=agent id=7 owner=0 name=CC\n") == Err(BadValue("owner"))
expect decoded("account v1 kind=agent id=7 name=CC\n") == Err(MissingField("owner"))
expect decoded("account v1 kind=agent github=1 login=a role=member name=b\n") == Err(MissingField("id"))
expect decoded("account v1 kind=bot id=18446744073709551616 owner=5 name=b\n") == Err(BadNumber("id"))
expect AccountCodec.decode([0x61, 0xff, '\n']).map_ok(|_| {}) == Err(NotUtf8)

# What will not encode: a name the rule refuses, one untrimmed, a login
# GitHub would not give.
expect AccountCodec.encode(human({ name: "", role: Member })) == Err(NameRefused(Empty))
expect AccountCodec.encode(human({ name: "a\nrole=admin", role: Member })) == Err(NameRefused(ControlCharacter))
expect AccountCodec.encode(human({ name: " Ann", role: Member })) == Err(NameUntrimmed)
expect AccountCodec.encode(Principal.Agent({ id: aid(1), owner: gid(1), name: "" })) == Err(NameRefused(Empty))
expect
	AccountCodec.encode(Principal.Human({ id: gid(1), login: "bad login", name: "b", role: Member }))
		== Err(LoginRefused)
