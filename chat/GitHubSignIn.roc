## **SIGNING IN WITH GITHUB, AS A STATE MACHINE** (the Roc chat's auth
## design, sections 2 and 5): each step a state of its own, an opaque type
## only this module makes, and each transition a pure function of the state
## before it and the facts a host supplies. A host answers facts (the
## state's signature held, the nonce was spent before, GitHub said who
## this is); every verdict is here. So no step can be skipped: there is no
## code to exchange before the state is checked, and no account before the
## identity is known.
##
##     /login                Started       start: a state minted, for the host to sign
##     /login/github         CameBack      came_back: the state and GitHub's code returned
##                           StateChecked  check: OAuthState.check, and the nonce spent once
##     (host asks GitHub)    IdentityKnown identify: GitHub's id and login
##                           resolve:      SignedIn an existing account's new session
##                                         NeedsName a new human, asked for a name
##                                         Refused
##     /login/name           Pending       resume: the pending sign-up, back from this browser
##                           name:         Created a new account and its session
##                                         SignedIn (an account made meanwhile), NameRefused, Refused
##
## **Sign-up is open (Steve):** any GitHub account may make an account,
## giving a display name (DisplayName's rule). An account is its GitHub id;
## its login is only what GitHub last called it, so a renamed login signs
## in to the same account, and a login another id gave up is a new account.
## **The first admin** is the GitHub id the settings name, made admin when
## its account is made and only while there is no admin yet. Pure.
import Ascii
import DisplayName
import GitHubLogin
import OAuthState
import Principal
import Session
import Stored

GitHubSignIn := [].{

	## **WHY A SIGN-IN IS REFUSED**, one name each.
	Refusal : [
		## The state did not come back signed by us (missing, or forged).
		StateForged,

		## The state is not this browser's (its cookie is missing or holds
		## another nonce): a login CSRF.
		StateMismatched,

		## The state is older than OAuthState's lifetime, or from the future.
		StateExpired,

		## The state's nonce was spent before: a replay.
		StateReused,

		## GitHub sent the browser back with no code: the person said no.
		GitHubDenied,

		## The code is not one GitHub would send.
		NotACode,

		## The host could not exchange the code, or ask GitHub who it is.
		GitHubUnreachable,

		## GitHub's answer is not an identity: an id of 0, or no login.
		BadIdentity,

		## The GitHub id's account was retired: it does not sign up again.
		Barred,

		## The pending sign-up did not come back signed by us.
		PendingForged,

		## The pending sign-up is not this browser's.
		PendingMismatched,

		## The pending sign-up is older than OAuthState's lifetime.
		PendingExpired,
	]

	## **THE SETTINGS THE FLOW IS GIVEN**: the GitHub id of the first admin,
	## if any is named; and the GitHub ids barred from signing up again
	## (their accounts retired).
	Settings : {
		first_admin : [Unnamed, Named(Principal.GitHubId)],
		barred : List(Principal.GitHubId),
	}

	## **A NEW SESSION'S FACTS**, the host's: its public number, and the
	## hash of the cookie's random secret.
	NewSession : {
		id : Principal.SessionId,
		token_hash : Stored.SecretHash,
	}

	## Signed in: the account (its login brought up to date, and `Renamed`
	## when the host must store it again) and the new session.
	SignedIn : {
		account : Principal,
		login : [Unchanged, Renamed],
		session : Session,
	}

	## **STARTED**: a state minted for this browser.
	Started :: OAuthState.Fields.{

		## A state of the host's random `nonce`, at least 16 bytes.
		start : { nonce : List(U8), now : I64 } -> Try(GitHubSignIn.Started, [WeakNonce])
		start = |{ nonce, now }|
			if List.len(nonce) < min_nonce_bytes {
				Err(WeakNonce)
			} else {
				Ok(GitHubSignIn.Started.(OAuthState.issue({ nonce, now })))
			}

		## The state's fields, for the host to sign into GitHub's `state`,
		## its nonce set in this browser's state cookie too.
		state : GitHubSignIn.Started -> OAuthState.Fields
		state = |GitHubSignIn.Started.(fields)| fields
	}

	## **CAME BACK**: GitHub sent the browser back, with the state and a
	## code.
	CameBack :: { state : OAuthState.Fields, code : List(U8) }.{

		## From the facts of the return: the state, if its signature held;
		## and GitHub's answer, a code or not. A state not signed by us is
		## said first, whatever GitHub answered.
		came_back : {
			state : [Signed(OAuthState.Fields), Unsigned],
			answer : [Code(List(U8)), Denied],
		} -> Try(GitHubSignIn.CameBack, GitHubSignIn.Refusal)
		came_back = |{ state, answer }|
			match (state, answer) {
				(Unsigned, _) => Err(StateForged)
				(Signed(_), Denied) => Err(GitHubDenied)
				(Signed(fields), Code(code)) =>
					if is_code(code) Ok(
						GitHubSignIn.CameBack.(
							{
								state: fields,
								code,
							},
						),
					) else Err(NotACode)
			}

		## The nonce the host spends, answering whether it was spent before.
		nonce : GitHubSignIn.CameBack -> List(U8)
		nonce = |GitHubSignIn.CameBack.(c)| c.state.nonce

		## **IS THE STATE THIS BROWSER'S, NOW, AND NEW?** OAuthState.check
		## (another browser's is said before the time), then the nonce's
		## first use.
		check : GitHubSignIn.CameBack,
		{
			cookie : OAuthState.Cookie,
			now : I64,
			nonce_use : [FirstUse, UsedBefore],
		} -> Try(GitHubSignIn.StateChecked, GitHubSignIn.Refusal)
		check = |
			GitHubSignIn.CameBack.(c),
			{
				cookie,
				now,
				nonce_use,
			},
		|
			match OAuthState.check(c.state, { cookie, now }) {
				Mismatched => Err(StateMismatched)
				Expired => Err(StateExpired)
				Valid =>
					match nonce_use {
						UsedBefore => Err(StateReused)
						FirstUse => Ok(
							GitHubSignIn.StateChecked.(
								{
									nonce: c.state.nonce,
									code: c.code,
								},
							),
						)
					}
			}
	}

	## **STATE CHECKED**: the code may be exchanged now, and only now.
	StateChecked :: { nonce : List(U8), code : List(U8) }.{

		## The code, for the host to exchange at GitHub.
		code : GitHubSignIn.StateChecked -> List(U8)
		code = |GitHubSignIn.StateChecked.(c)| c.code

		## From GitHub's answer to `/user` (by the host, with the token it
		## got for the code, then forgot): the id and the login, or a
		## failure.
		identify : GitHubSignIn.StateChecked,
		[
			Identified({ id : U64, login : List(U8) }),
			Failed,
		] -> Try(GitHubSignIn.IdentityKnown, GitHubSignIn.Refusal)
		identify = |GitHubSignIn.StateChecked.(c), answer|
			match answer {
				Failed => Err(GitHubUnreachable)
				Identified({ id, login }) =>
					match (Principal.GitHubId.from_u64(id), GitHubLogin.from_utf8(login)) {
						(Ok(github), Ok(known)) => Ok(
							GitHubSignIn.IdentityKnown.(
								{
									nonce: c.nonce,
									github,
									login: known,
								},
							),
						)
						_ => Err(BadIdentity)
					}
			}
	}

	## **IDENTITY KNOWN**: who GitHub says this is.
	IdentityKnown :: {
		nonce : List(U8),
		github : Principal.GitHubId,
		login : GitHubLogin,
	}.{

		## The GitHub id.
		github : GitHubSignIn.IdentityKnown -> Principal.GitHubId
		github = |GitHubSignIn.IdentityKnown.(k)| k.github

		## **WHOSE SIGN-IN IS THIS?** In order: a barred id is refused; an
		## id with an account signs in to it (its login brought up to date);
		## any other id is a new human, asked for a name.
		resolve : GitHubSignIn.IdentityKnown,
		{
			accounts : List(Principal),
			settings : GitHubSignIn.Settings,
			session : GitHubSignIn.NewSession,
			now : I64,
		} -> [
			SignedIn(GitHubSignIn.SignedIn),
			NeedsName(GitHubSignIn.Pending),
			Refused(GitHubSignIn.Refusal),
		]
		resolve = |
			GitHubSignIn.IdentityKnown.(k),
			{
				accounts,
				settings,
				session,
				now,
			},
		|
			match known_account({
				github: k.github,
				login: k.login,
				accounts,
				settings,
				session,
				now,
			}) {
				Barred => Refused(Barred)
				Known(signed_in) => SignedIn(signed_in)
				Unknown =>
					NeedsName(
						GitHubSignIn.Pending.(
							{
								nonce: k.nonce,
								github: k.github,
								login: k.login,
								issued_at: now,
							},
						),
					)
			}
	}

	## A pending sign-up's fields: what the host signs into a cookie, and
	## hands back as it decoded them once the signature held.
	PendingFields : {
		nonce : List(U8),
		github : U64,
		login : List(U8),
		issued_at : I64,
	}

	## **PENDING**: a new human, between GitHub and their name.
	Pending :: {
		nonce : List(U8),
		github : Principal.GitHubId,
		login : GitHubLogin,
		issued_at : I64,
	}.{

		## Its fields, for the host to sign.
		fields : GitHubSignIn.Pending -> GitHubSignIn.PendingFields
		fields = |GitHubSignIn.Pending.(p)| {
			nonce: p.nonce,
			github: p.github.to_u64(),
			login: Str.to_utf8(p.login.to_str()),
			issued_at: p.issued_at,
		}

		## **BACK FROM THIS BROWSER, IN TIME?** The pending sign-up is held
		## to the state cookie's nonce and to OAuthState's lifetime, as the
		## state was: a pending sign-up another browser was handed (a login
		## CSRF into a stranger's new account) is refused.
		resume : {
			pending : [Signed(GitHubSignIn.PendingFields), Unsigned],
			cookie : OAuthState.Cookie,
			now : I64,
		} -> Try(GitHubSignIn.Pending, GitHubSignIn.Refusal)
		resume = |
			{
				pending,
				cookie,
				now,
			},
		|
			match pending {
				Unsigned => Err(PendingForged)
				Signed(p) =>
					match OAuthState.check(
						{ nonce: p.nonce, issued_at: p.issued_at },
						{ cookie, now },
					) {
						Mismatched => Err(PendingMismatched)
						Expired => Err(PendingExpired)
						Valid =>
							match (
								Principal.GitHubId.from_u64(p.github),
								GitHubLogin.from_utf8(p.login),
							) {
								(Ok(github), Ok(login)) =>
									Ok(
										GitHubSignIn.Pending.(
											{
												nonce: p.nonce,
												github,
												login,
												issued_at: p.issued_at,
											},
										),
									)

								_ => Err(BadIdentity)
							}
					}
			}

		## **THE NAME GIVEN**: in order, a barred id is refused; an id
		## whose account was made meanwhile (a second tab) signs in to it,
		## the name unused; a name the rule refuses is said, to ask again;
		## otherwise the account is made, admin only as the first admin.
		name : GitHubSignIn.Pending,
		{
			name : List(U8),
			accounts : List(Principal),
			settings : GitHubSignIn.Settings,
			session : GitHubSignIn.NewSession,
			now : I64,
		} -> [
			Created({ account : Principal, session : Session }),
			SignedIn(GitHubSignIn.SignedIn),
			NameRefused(DisplayName.Problem),
			Refused(GitHubSignIn.Refusal),
		]
		name = |
			GitHubSignIn.Pending.(p),
			{
				name,
				accounts,
				settings,
				session,
				now,
			},
		|
			match known_account({
				github: p.github,
				login: p.login,
				accounts,
				settings,
				session,
				now,
			}) {
				Barred => Refused(Barred)
				Known(signed_in) => SignedIn(signed_in)
				Unknown =>
					match DisplayName.from_utf8(name) {
						Err(problem) => NameRefused(problem)
						Ok(chosen) =>
							Created({
								account: Principal.Human({
									id: p.github,
									login: p.login.to_str(),
									name: chosen.to_str(),
									role: first_role({
										github: p.github,
										accounts,
										settings,
									}),
								}),
								session: started(p.github, { session, now }),
							})
					}
			}
	}
}

## The fewest bytes of randomness a state's nonce may have.
min_nonce_bytes : U64
min_nonce_bytes = 16

## The most bytes a GitHub code may have.
max_code_bytes : U64
max_code_bytes = 64

## A code as GitHub sends one: 1 to 64 bytes of letters, digits, `-`, `_`.
is_code : List(U8) -> Bool
is_code = |code|
	code != [] and List.len(code) <= max_code_bytes and List.all(
		code,
		|c| Ascii.is_alphanumeric(c) or c == '-' or c == '_',
	)

## The id's standing: barred, an account it signs in to, or none yet.
known_account : {
	github : Principal.GitHubId,
	login : GitHubLogin,
	accounts : List(Principal),
	settings : GitHubSignIn.Settings,
	session : GitHubSignIn.NewSession,
	now : I64,
} -> [
	Barred,
	Known(GitHubSignIn.SignedIn),
	Unknown,
]
known_account = |
	{
		github,
		login,
		accounts,
		settings,
		session,
		now,
	},
|
	if List.contains(settings.barred, github) {
		Barred
	} else {
		match Principal.find(accounts, Principal.Id.Human(github)) {
			Err(NoSuchPrincipal) => Unknown
			Ok(Agent(_)) | Ok(Bot(_)) => crash "known_account: a human's id finds a human"
			Ok(Human(h)) => {
				fresh = login.to_str()
				Known({
					account: Principal.Human({ ..h, login: fresh }),
					login: if h.login == fresh Unchanged else Renamed,
					session: started(github, { session, now }),
				})
			}
		}
	}

## The role a new human's account is made with: admin for the first admin
## the settings name, while no human is an admin yet; member otherwise.
first_role : {
	github : Principal.GitHubId,
	accounts : List(Principal),
	settings : GitHubSignIn.Settings,
} -> Principal.Role
first_role = |
	{
		github,
		accounts,
		settings,
	},
| {
	has_admin = List.any(
		accounts,
		|a|
			match a {
				Human(h) => h.role == Admin
				Agent(_) | Bot(_) => Bool.False
			},
	)
	match settings.first_admin {
		Named(first) if first == github and !has_admin => Admin
		_ => Member
	}
}

## A session for `github`, from the host's facts.
started : Principal.GitHubId, { session : GitHubSignIn.NewSession, now : I64 } -> Session
started = |github, { session, now }|
	Session.start({
		id: session.id,
		human: github,
		token_hash: session.token_hash,
		now,
	})

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

## A test's human: GitHub id `n`, its login, name and role.
human : U64,
{
	login : Str,
	name : Str,
	role : Principal.Role,
} -> Principal
human = |
	n,
	{
		login,
		name,
		role,
	},
| Principal.Human({
	id: gid(n),
	login,
	name,
	role,
})

# The cast: Boss (GitHub id 1), the admin; Ann (2), a member; Ann's agent,
# whose owner id is Ann's.
boss : Principal
boss = human(
	1,
	{
		login: "boss",
		name: "Boss",
		role: Admin,
	},
)

ann : Principal
ann = human(
	2,
	{
		login: "ann",
		name: "Ann",
		role: Member,
	},
)

ann_agent : Principal
ann_agent = Principal.Agent({
	id: aid(1),
	owner: gid(2),
	name: "Ann's agent",
})

## This browser's nonce, 16 bytes; another browser's.
this_nonce : List(U8)
this_nonce = Str.to_utf8("q7Zr2Lx9q7Zr2Lx9")

that_nonce : List(U8)
that_nonce = Str.to_utf8("Wm4kPq8sWm4kPq8s")

new_session : GitHubSignIn.NewSession
new_session = { id: sid(5), token_hash: token(0x42) }

## Open sign-up, Boss the first admin, GitHub id 66 barred.
usual_settings : GitHubSignIn.Settings
usual_settings = { first_admin: Named(gid(1)), barred: [gid(66)] }

# ── STARTED
expect GitHubSignIn.Started.start({
	nonce: List.repeat('n', 15),
	now: 1000,
}).map_ok(GitHubSignIn.Started.state) == Err(WeakNonce)
expect GitHubSignIn.Started.start({
	nonce: [],
	now: 1000,
}).map_ok(GitHubSignIn.Started.state) == Err(WeakNonce)
expect
	GitHubSignIn.Started.start({ nonce: this_nonce, now: 1000 }).map_ok(GitHubSignIn.Started.state)
		== Ok({ nonce: this_nonce, issued_at: 1000 })

## **ONE SIGN-IN, FROM /login TO WHOSE IT IS**: every fact a host would
## supply, so each hostile case below is the usual run with one fact
## changed.
Facts : {
	## When /login minted the state (this browser's nonce).
	minted_at : I64,

	## The state as it came back: ours, signed; not signed by us; or another
	## state we signed (another browser's).
	state_back : [
		Ours,
		Forged,
		Swapped(OAuthState.Fields),
	],
	answer : [Code(List(U8)), Denied],
	cookie : OAuthState.Cookie,
	back_at : I64,
	nonce_use : [FirstUse, UsedBefore],
	github : [Identified({ id : U64, login : List(U8) }), Failed],
	accounts : List(Principal),
	settings : GitHubSignIn.Settings,
}

## Ann's GitHub (id 2, `ann`), signing in a minute after /login, with no
## account yet.
usual : Facts
usual = {
	minted_at: 1000,
	state_back: Ours,
	answer: Code(Str.to_utf8("e72e16c7e42f292c6912")),
	cookie: Sent(this_nonce),
	back_at: 1060,
	nonce_use: FirstUse,
	github: Identified({ id: 2, login: Str.to_utf8("ann") }),
	accounts: [boss, ann_agent],
	settings: usual_settings,
}

Resolved : [
	SignedIn(GitHubSignIn.SignedIn),
	NeedsName(GitHubSignIn.Pending),
	Refused(GitHubSignIn.Refusal),
]

## The facts, through every transition up to `resolve`.
resolved_by : Facts -> Try(Resolved, GitHubSignIn.Refusal)
resolved_by = |f| {
	minted =
		match GitHubSignIn.Started.start({ nonce: this_nonce, now: f.minted_at }) {
			Ok(s) => s
			Err(WeakNonce) => crash "resolved_by: a test's nonce is 16 bytes"
		}
	back =
		match f.state_back {
			Ours => Signed(minted.state())
			Forged => Unsigned
			Swapped(fields) => Signed(fields)
		}
	came = GitHubSignIn.CameBack.came_back({ state: back, answer: f.answer })?
	checked = came.check({
		cookie: f.cookie,
		now: f.back_at,
		nonce_use: f.nonce_use,
	})?
	known = checked.identify(f.github)?
	Ok(
		known.resolve({
			accounts: f.accounts,
			settings: f.settings,
			session: new_session,
			now: f.back_at,
		}),
	)
}

## A human account, every field, for a test to compare (Principal has no
## `==`).
Seen : {
	id : Principal.GitHubId,
	login : Str,
	name : Str,
	role : Principal.Role,
}

seen : Principal -> Seen
seen = |account|
	match account {
		Human(h) => h
		Agent(_) | Bot(_) => crash "seen: the flow makes and signs in humans alone"
	}

## What resolving says, comparably.
Said : [
	SignedIn(
		{
			account : Seen,
			login : [Unchanged, Renamed],
			session : Session,
		},
	),
	NeedsName({ github : U64, login : Str }),
	Refused(GitHubSignIn.Refusal),
]

said : Facts -> Said
said = |f|
	match resolved_by(f) {
		Err(why) => Refused(why)
		Ok(Refused(why)) => Refused(why)
		Ok(SignedIn(s)) => SignedIn({
			account: seen(s.account),
			login: s.login,
			session: s.session,
		})
		Ok(NeedsName(p)) => {
			fields = p.fields()
			match Str.from_utf8(fields.login) {
				Ok(login) => NeedsName({ github: fields.github, login })
				Err(_) => crash "said: a pending login passed GitHubLogin's rule, so it is UTF-8"
			}
		}
	}

## The session a sign-in at 1060 makes for GitHub id `n`.
session_for : U64 -> Session
session_for = |n| Session.start({
	id: sid(5),
	human: gid(n),
	token_hash: token(0x42),
	now: 1060,
})

# ── RESOLVING: the usual runs.
# Ann, no account yet: a new human, asked for a name.
expect said(usual) == NeedsName({ github: 2, login: "ann" })

# Ann with an account: signed in to it, a session made.
expect
	said({ ..usual, accounts: [boss, ann] })
		== SignedIn({
			account: seen(ann),
			login: Unchanged,
			session: session_for(2),
		})

# **A GITHUB ID THAT CHANGED ITS LOGIN IS THE SAME ACCOUNT**: Ann renamed
# to `ann-b` signs in to Ann's account, its login brought up to date and
# said `Renamed` (to store); her name and role are untouched.
expect
	said({
		..usual,
		accounts: [boss, ann],
		github: Identified({ id: 2, login: Str.to_utf8("ann-b") }),
	})
		== SignedIn({
			account: { ..seen(ann), login: "ann-b" },
			login: Renamed,
			session: session_for(2),
		})

# **A LOGIN REUSED BY ANOTHER ID IS ANOTHER ACCOUNT**: GitHub id 3 now
# calling itself `ann` is never Ann; it is a new human.
expect
	said({
		..usual,
		accounts: [boss, ann],
		github: Identified({ id: 3, login: Str.to_utf8("ann") }),
	})
		== NeedsName({ github: 3, login: "ann" })

# An agent's owner id with no human account: agents never sign in, so it is
# a new human.
expect said({ ..usual, accounts: [ann_agent] }) == NeedsName({ github: 2, login: "ann" })

# The first admin's existing account is not promoted by signing in.
expect
	said({
		..usual,
		accounts: [ann],
		settings: { ..usual_settings, first_admin: Named(gid(2)) },
	})
		== SignedIn({
			account: seen(ann),
			login: Unchanged,
			session: session_for(2),
		})

# ── RESOLVING: the hostile runs.
# A state not signed by us: refused, whatever GitHub said.
expect said({ ..usual, state_back: Forged }) == Refused(StateForged)
expect said({
	..usual,
	state_back: Forged,
	answer: Denied,
}) == Refused(StateForged)

# **A STATE FROM ANOTHER BROWSER** (a login CSRF): another browser's state,
# signed by us, back with this browser's cookie; or this browser's state,
# back with another's cookie, or none.
expect said({
	..usual,
	state_back: Swapped({ nonce: that_nonce, issued_at: 1000 }),
}) == Refused(StateMismatched)
expect said({ ..usual, cookie: Sent(that_nonce) }) == Refused(StateMismatched)
expect said({ ..usual, cookie: Unsent }) == Refused(StateMismatched)

# **A REUSED STATE**: the nonce spent before, though all else is good.
expect said({ ..usual, nonce_use: UsedBefore }) == Refused(StateReused)
expect said({
	..usual,
	nonce_use: UsedBefore,
	accounts: [ann],
}) == Refused(StateReused)

# Another browser's reused state: the mismatch is said first.
expect said({
	..usual,
	nonce_use: UsedBefore,
	cookie: Sent(that_nonce),
}) == Refused(StateMismatched)

# The state's window: ten minutes from its minting, never before it.
expect said({ ..usual, back_at: 1599 }) == NeedsName({ github: 2, login: "ann" })
expect said({ ..usual, back_at: 1600 }) == Refused(StateExpired)
expect said({ ..usual, back_at: 999 }) == Refused(StateExpired)

# GitHub's answer: no code, or not a code.
expect said({ ..usual, answer: Denied }) == Refused(GitHubDenied)
expect
	List.all(
		[
			"",
			Str.repeat("c", 65),
			"e72e 16c7",
			"e72e/16c7",
			"e72e16c7\n",
			"code=x",
		],
		|bad| said({ ..usual, answer: Code(Str.to_utf8(bad)) }) == Refused(NotACode),
	)
expect said({
	..usual,
	answer: Code(Str.to_utf8(Str.repeat("c", 64))),
}) == NeedsName({ github: 2, login: "ann" })
expect said({
	..usual,
	answer: Code(Str.to_utf8("a-b_C9")),
}) == NeedsName({ github: 2, login: "ann" })

# GitHub unreachable, or an answer that is no identity.
expect said({ ..usual, github: Failed }) == Refused(GitHubUnreachable)
expect said({
	..usual,
	github: Identified({ id: 0, login: Str.to_utf8("ann") }),
}) == Refused(BadIdentity)
expect said({ ..usual, github: Identified({ id: 2, login: [] }) }) == Refused(BadIdentity)
expect said({
	..usual,
	github: Identified({ id: 2, login: Str.to_utf8("ann ann") }),
}) == Refused(BadIdentity)
expect said({ ..usual, github: Identified({ id: 2, login: [0x61, 0xff] }) }) == Refused(BadIdentity)

# A barred id: refused, even with an account still listed.
expect said({
	..usual,
	github: Identified({ id: 66, login: Str.to_utf8("gone") }),
}) == Refused(Barred)
expect
	said({
		..usual,
		accounts: [
			human(
				66,
				{
					login: "gone",
					name: "Gone",
					role: Member,
				},
			),
		],
		github: Identified({ id: 66, login: Str.to_utf8("gone") }),
	})
		== Refused(Barred)

# ── THE NAME STEP
## The pending sign-up the usual run leaves, its facts as the host would
## hand them back.
pending_of : Facts -> GitHubSignIn.PendingFields
pending_of = |f|
	match resolved_by(f) {
		Ok(NeedsName(p)) => p.fields()
		_ => crash "pending_of: the run asks for a name"
	}

usual_pending : GitHubSignIn.PendingFields
usual_pending = pending_of(usual)

expect usual_pending == {
	nonce: this_nonce,
	github: 2,
	login: Str.to_utf8("ann"),
	issued_at: 1060,
}

## The facts of the name's POST.
Naming : {
	pending : [Signed(GitHubSignIn.PendingFields), Unsigned],
	cookie : OAuthState.Cookie,
	at : I64,
	name : List(U8),
	accounts : List(Principal),
	settings : GitHubSignIn.Settings,
}

## Ann names herself "Ann B." a minute later.
usual_naming : Naming
usual_naming = {
	pending: Signed(usual_pending),
	cookie: Sent(this_nonce),
	at: 1120,
	name: Str.to_utf8("Ann B."),
	accounts: [boss, ann_agent],
	settings: usual_settings,
}

## What naming says, comparably.
NameSaid : [
	Created({ account : Seen, session : Session }),
	SignedIn(
		{
			account : Seen,
			login : [Unchanged, Renamed],
			session : Session,
		},
	),
	NameRefused(DisplayName.Problem),
	Refused(GitHubSignIn.Refusal),
]

name_said : Naming -> NameSaid
name_said = |n|
	match GitHubSignIn.Pending.resume({
		pending: n.pending,
		cookie: n.cookie,
		now: n.at,
	}) {
		Err(why) => Refused(why)
		Ok(p) =>
			match p.name({
				name: n.name,
				accounts: n.accounts,
				settings: n.settings,
				session: new_session,
				now: n.at,
			}) {
				Created(c) => Created({ account: seen(c.account), session: c.session })
				SignedIn(s) => SignedIn({
					account: seen(s.account),
					login: s.login,
					session: s.session,
				})
				NameRefused(problem) => NameRefused(problem)
				Refused(why) => Refused(why)
			}
	}

## The session a naming at 1120 makes for GitHub id `n`.
named_session : U64 -> Session
named_session = |n| Session.start({
	id: sid(5),
	human: gid(n),
	token_hash: token(0x42),
	now: 1120,
})

## Ann's new account, named `name`, with `role`.
ann_as : Str, Principal.Role -> Seen
ann_as = |name, role| {
	id: gid(2),
	login: "ann",
	name,
	role,
}

# Made: a member, named as given, trimmed; a session with it.
expect name_said(usual_naming) == Created({
	account: ann_as("Ann B.", Member),
	session: named_session(2),
})
expect
	name_said({ ..usual_naming, name: Str.to_utf8("  Ann B.  ") })
		== Created({ account: ann_as("Ann B.", Member), session: named_session(2) })
expect
	name_said({ ..usual_naming, name: Str.to_utf8("🦊") })
		== Created({ account: ann_as("🦊", Member), session: named_session(2) })

# **THE NAME RULE**: empty, spaces alone, over 64 bytes, a control
# character, a bidi control, not UTF-8: each said, so the form asks again.
expect name_said({ ..usual_naming, name: [] }) == NameRefused(Empty)
expect name_said({ ..usual_naming, name: Str.to_utf8("   ") }) == NameRefused(Empty)
expect name_said({ ..usual_naming, name: Str.to_utf8(Str.repeat("n", 65)) }) == NameRefused(TooLong)
expect
	name_said({ ..usual_naming, name: Str.to_utf8(Str.repeat("n", 64)) })
		== Created({ account: ann_as(Str.repeat("n", 64), Member), session: named_session(2) })
expect name_said({
	..usual_naming,
	name: Str.to_utf8("Ann\nrole=admin"),
}) == NameRefused(ControlCharacter)
expect name_said({ ..usual_naming, name: Str.to_utf8("\u(202E)nnA") }) == NameRefused(BidiControl)
expect name_said({ ..usual_naming, name: [0x41, 0xff] }) == NameRefused(NotUtf8)

# **THE FIRST ADMIN**: the named id, while no human is an admin.
first_ann : GitHubSignIn.Settings
first_ann = { ..usual_settings, first_admin: Named(gid(2)) }

expect
	name_said({
		..usual_naming,
		settings: first_ann,
		accounts: [ann_agent],
	})
		== Created({ account: ann_as("Ann B.", Admin), session: named_session(2) })
expect
	name_said({
		..usual_naming,
		settings: first_ann,
		accounts: [boss],
	})
		== Created({ account: ann_as("Ann B.", Member), session: named_session(2) })
expect name_said({ ..usual_naming, accounts: [] }) == Created({
	account: ann_as("Ann B.", Member),
	session: named_session(2),
})
expect
	name_said({
		..usual_naming,
		settings: { ..usual_settings, first_admin: Unnamed },
		accounts: [],
	})
		== Created({ account: ann_as("Ann B.", Member), session: named_session(2) })

# An account made meanwhile (a second tab): signed in to it, no second
# account, the name unused.
expect
	name_said({ ..usual_naming, accounts: [boss, ann] })
		== SignedIn({
			account: seen(ann),
			login: Unchanged,
			session: named_session(2),
		})

# Barred meanwhile.
expect name_said({
	..usual_naming,
	settings: { ..usual_settings, barred: [gid(2)] },
}) == Refused(Barred)

# **THE PENDING SIGN-UP, HOSTILE**: not signed by us; handed to another
# browser (a login CSRF into a stranger's new account); without a cookie;
# stale; or signed but not an identity.
expect name_said({ ..usual_naming, pending: Unsigned }) == Refused(PendingForged)
expect name_said({ ..usual_naming, cookie: Sent(that_nonce) }) == Refused(PendingMismatched)
expect name_said({ ..usual_naming, cookie: Unsent }) == Refused(PendingMismatched)
expect
	name_said({ ..usual_naming, at: 1659 })
		== Created({
			account: ann_as("Ann B.", Member),
			session: Session.start({
				id: sid(5),
				human: gid(2),
				token_hash: token(0x42),
				now: 1659,
			}),
		})
expect name_said({ ..usual_naming, at: 1660 }) == Refused(PendingExpired)
expect name_said({ ..usual_naming, at: 1059 }) == Refused(PendingExpired)
expect name_said({
	..usual_naming,
	pending: Signed({ ..usual_pending, github: 0 }),
}) == Refused(BadIdentity)
expect name_said({
	..usual_naming,
	pending: Signed({ ..usual_pending, login: [] }),
}) == Refused(BadIdentity)
