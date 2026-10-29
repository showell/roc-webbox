## **WHO IS ACTING** (the Roc chat's auth design, section 1): every request
## acts as exactly one principal, a human signed in with GitHub, or an agent
## or a bot a human owns. Each kind's id is a type of its own, so a GitHub
## id, an agent's id and a key's id cannot be passed for one another. Pure;
## nothing here knows of conversations, so a resource other than the chat's
## (a database, a file system) takes the same principals.
Principal := [
	## A person, signed in with GitHub. Keyed by GitHub's numeric id, which
	## never changes; the login (which can) is kept for display and the
	## GitHub link. The name is the one they chose, real or not.
	Human(
		{
			id : Principal.GitHubId,
			login : Str,
			name : Str,
			role : Principal.Role,
		},
	),

	## An account a human made and owns (Claude, CC): it never signs in
	## through a browser, and acts only through API keys.
	Agent(
		{
			id : Principal.AgentId,
			name : Str,
			owner : Principal.GitHubId,
		},
	),

	## An integration (the GitHub commit bot), fed by an outside system's
	## webhook rather than a model; owned by a human, as an agent is.
	Bot(
		{
			id : Principal.AgentId,
			name : Str,
			owner : Principal.GitHubId,
		},
	),
].{

	## **A HUMAN'S ROLE**: an admin manages accounts (Admin.roc); set for
	## the first account by the bootstrap setting, changed only by an admin.
	Role : [Admin, Member]

	## GitHub's numeric user id, as GitHub's `/user` gives it. Opaque: made
	## only by `from_u64`, which refuses 0 (GitHub's ids start at 1, and a
	## 0 is what a field that failed to decode reads as).
	GitHubId :: U64.{
		from_u64 : U64 -> Try(Principal.GitHubId, [NotAnId])
		from_u64 = |n| if n == 0 Err(NotAnId) else Ok(Principal.GitHubId.(n))

		to_u64 : Principal.GitHubId -> U64
		to_u64 = |Principal.GitHubId.(n)| n

		is_eq : _
	}

	## An agent's or a bot's id, from the chat's own counter (one counter
	## for both kinds). Opaque: made only by `from_u64`, which refuses 0.
	AgentId :: U64.{
		from_u64 : U64 -> Try(Principal.AgentId, [NotAnId])
		from_u64 = |n| if n == 0 Err(NotAnId) else Ok(Principal.AgentId.(n))

		to_u64 : Principal.AgentId -> U64
		to_u64 = |Principal.AgentId.(n)| n

		is_eq : _
	}

	## An API key's public id, shown in lists and written in the audit
	## trail; never the key's secret. Opaque: made only by `from_u64`,
	## which refuses 0.
	KeyId :: U64.{
		from_u64 : U64 -> Try(Principal.KeyId, [NotAnId])
		from_u64 = |n| if n == 0 Err(NotAnId) else Ok(Principal.KeyId.(n))

		to_u64 : Principal.KeyId -> U64
		to_u64 = |Principal.KeyId.(n)| n

		is_eq : _
	}

	## A sign-in session's public number, written in the audit trail; never
	## the cookie's random value, which is the session's secret. Opaque:
	## made only by `from_u64`, which refuses 0.
	SessionId :: U64.{
		from_u64 : U64 -> Try(Principal.SessionId, [NotAnId])
		from_u64 = |n| if n == 0 Err(NotAnId) else Ok(Principal.SessionId.(n))

		to_u64 : Principal.SessionId -> U64
		to_u64 = |Principal.SessionId.(n)| n

		is_eq : _
	}

	## **WHICH PRINCIPAL, BY ID ALONE**: what a participant list, a key's
	## `acts_as` and the audit trail hold. Two principals are the same one
	## when their ids are equal; a name or a role is no part of it.
	Id := [
		Human(Principal.GitHubId),
		Agent(Principal.AgentId),
		Bot(Principal.AgentId),
	].{
		is_eq : _
	}

	## The principal's id.
	id : Principal -> Principal.Id
	id = |principal|
		match principal {
			Human(h) => Principal.Id.Human(h.id)
			Agent(a) => Principal.Id.Agent(a.id)
			Bot(b) => Principal.Id.Bot(b.id)
		}

	## **THE HUMAN A PRINCIPAL ANSWERS TO**: a human, itself; an agent or a
	## bot, its owner.
	answers_to : Principal -> Principal.GitHubId
	answers_to = |principal|
		match principal {
			Human(h) => h.id
			Agent(a) => a.owner
			Bot(b) => b.owner
		}

	## The principal with id `wanted` among `accounts`, or `NoSuchPrincipal`
	## (never made, or retired).
	find : List(Principal), Principal.Id -> Try(Principal, [NoSuchPrincipal])
	find = |accounts, wanted|
		match List.find_first(accounts, |p| Principal.id(p) == wanted) {
			Ok(found) => Ok(found)
			Err(_) => Err(NoSuchPrincipal)
		}

	## The human with GitHub id `human` has an account among `accounts`:
	## what an agent's key, and a human's election, stand on.
	has_account : List(Principal), Principal.GitHubId -> Bool
	has_account = |accounts, human|
		match find(accounts, Principal.Id.Human(human)) {
			Ok(Human(_)) => Bool.True
			Ok(Agent(_)) | Ok(Bot(_)) => crash "Principal.has_account: a human's id finds a human"
			Err(NoSuchPrincipal) => Bool.False
		}

	## **THE AUTHORITY A PRINCIPAL ACTS WITH, AS THE ACCOUNTS SAY NOW**
	## (design section 9): `Admin` for an admin human, and for an agent
	## whose owner is an admin human among `accounts`; `Member` for anyone
	## else. A bot is never `Admin`: the design grants admin to "an agent an
	## admin owns", and a bot is fed by an outside system. Read from the
	## accounts at each request, so an owner's demotion or retirement takes
	## their agent's authority with it.
	authority : Principal, List(Principal) -> Principal.Role
	authority = |principal, accounts|
		match principal {
			Human(h) => h.role
			Bot(_) => Member
			Agent(a) =>
				match find(accounts, Principal.Id.Human(a.owner)) {
					Ok(Human(owner)) => owner.role
					Ok(Agent(_)) | Ok(Bot(_)) => crash "Principal.authority: a non-human"
					Err(NoSuchPrincipal) => Member
				}
		}
}

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

## A test's human: GitHub id `n`, its role.
person : U64, Principal.Role -> Principal
person = |n, role|
	Principal.Human({
		id: gid(n),
		login: "h${n.to_str()}",
		name: "H${n.to_str()}",
		role,
	})

## A test's agent or bot: its id, and its owner's GitHub id.
owned : [Agent, Bot], { id : U64, owner : U64 } -> Principal
owned = |kind, { id, owner }|
	match kind {
		Agent =>
			Principal.Agent({
				id: aid(id),
				name: "a${id.to_str()}",
				owner: gid(owner),
			})

		Bot =>
			Principal.Bot({
				id: aid(id),
				name: "b${id.to_str()}",
				owner: gid(owner),
			})
	}

boss : Principal
boss = person(1, Admin)

ann : Principal
ann = person(2, Member)

boss_agent : Principal
boss_agent = owned(Agent, { id: 1, owner: 1 })

boss_bot : Principal
boss_bot = owned(Bot, { id: 2, owner: 1 })

ann_agent : Principal
ann_agent = owned(Agent, { id: 3, owner: 2 })

## An agent whose owner is among no accounts.
orphan_agent : Principal
orphan_agent = owned(Agent, { id: 4, owner: 9 })

accounts : List(Principal)
accounts = [
	boss,
	ann,
	boss_agent,
	boss_bot,
	ann_agent,
	orphan_agent,
]

# The ids: 0 is refused for every kind, and kinds never compare equal.
expect Principal.GitHubId.from_u64(0) == Err(NotAnId)
expect Principal.AgentId.from_u64(0) == Err(NotAnId)
expect Principal.KeyId.from_u64(0) == Err(NotAnId)
expect Principal.SessionId.from_u64(0) == Err(NotAnId)
expect Principal.GitHubId.from_u64(583231).map_ok(Principal.GitHubId.to_u64) == Ok(583231)
expect Principal.Id.Agent(aid(1)) != Principal.Id.Bot(aid(1))
expect Principal.id(boss_agent) == Principal.Id.Agent(aid(1))
expect Principal.id(boss) == Principal.Id.Human(gid(1))

# answers_to: a human itself, an agent or a bot its owner.
expect Principal.answers_to(ann) == gid(2)
expect Principal.answers_to(boss_agent) == gid(1)
expect Principal.answers_to(boss_bot) == gid(1)

# find: by id, a name playing no part.
found : Principal.Id -> Try(Principal.Id, [NoSuchPrincipal])
found = |wanted| Principal.find(accounts, wanted).map_ok(Principal.id)

expect found(Principal.Id.Agent(aid(3))) == Ok(Principal.id(ann_agent))
expect found(Principal.Id.Bot(aid(3))) == Err(NoSuchPrincipal)
expect found(Principal.Id.Human(gid(9))) == Err(NoSuchPrincipal)

# has_account: a human's id alone; an agent's id never names a human.
expect Principal.has_account(accounts, gid(2))
expect !Principal.has_account(accounts, gid(9))
expect !Principal.has_account([boss_agent], gid(1))

# authority: one row a principal.
expect Principal.authority(boss, accounts) == Admin
expect Principal.authority(ann, accounts) == Member
expect Principal.authority(boss_agent, accounts) == Admin
expect Principal.authority(boss_bot, accounts) == Member
expect Principal.authority(ann_agent, accounts) == Member
expect Principal.authority(orphan_agent, accounts) == Member
# The owner retired: the agent's authority went with them.
expect Principal.authority(boss_agent, [boss_agent]) == Member
