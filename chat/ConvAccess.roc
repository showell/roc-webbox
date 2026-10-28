## **WHO MAY SEE A CONVERSATION, AND WHO ELECTS** (the Roc chat's auth
## design, section 4, with Steve's answers in 8 and 9): the chat's layer on
## Access.roc. A conversation is the resource; what makes it public is the
## chat's own rule, kept here:
## - a conversation of humans alone is always private;
## - one with an agent or a bot in it is public only while every human
##   involved (its human participants, and the owners of its agents and
##   bots) has elected public, and any one of them can withdraw.
## Who sees and who posts is then Access's, unchanged. Pure; the table of
## every viewer against every conversation is below.
import Access
import Principal

ConvAccess := [].{

	## A conversation's id, from the chat's own counter. Opaque: made only
	## by `from_u64`, which refuses 0.
	ConvId :: U64.{
		from_u64 : U64 -> Try(ConvAccess.ConvId, [NotAnId])
		from_u64 = |n| if n == 0 Err(NotAnId) else Ok(ConvAccess.ConvId.(n))

		to_u64 : ConvAccess.ConvId -> U64
		to_u64 = |ConvAccess.ConvId.(n)| n

		is_eq : _
	}

	## One human's election: the visibility they want for the conversation.
	Election : {
		human : Principal.GitHubId,
		visibility : [Private, Public],
	}

	## **A CONVERSATION AND ITS ELECTIONS, AS A STATE MACHINE**: opaque, so
	## `start` is the one way in (every human's election private) and
	## `elect` the one transition. `public_by` holds the humans whose
	## election is public now; a human not in it has elected private, or
	## never elected, which is the same.
	Conv :: {
		id : ConvAccess.ConvId,
		participants : List(Principal),
		public_by : List(Principal.GitHubId),
	}.{

		## A new conversation among `participants` (each once, by id),
		## private to every human involved. `NoParticipants` for none.
		start : { id : ConvAccess.ConvId, participants : List(Principal) } -> Try(
			ConvAccess.Conv,
			[NoParticipants],
		)
		start = |{ id, participants }| {
			once = List.fold(
				participants,
				[],
				|kept, p| {
					is_kept = List.any(kept, |k| Principal.id(k) == Principal.id(p))
					if is_kept kept else List.append(kept, p)
				},
			)
			if List.is_empty(once) {
				Err(NoParticipants)
			} else {
				Ok(
					ConvAccess.Conv.(
						{
							id,
							participants: once,
							public_by: [],
						},
					),
				)
			}
		}

		## The conversation's id.
		id : ConvAccess.Conv -> ConvAccess.ConvId
		id = |ConvAccess.Conv.(c)| c.id

		## Humans alone, or an agent or a bot among them.
		kind : ConvAccess.Conv -> [HumansOnly, WithAgents]
		kind = |ConvAccess.Conv.(c)|
			if List.all(
				c.participants,
				|p| match p {
					Human(_) => Bool.True
					Agent(_) | Bot(_) => Bool.False
				},
			) {
				HumansOnly
			} else {
				WithAgents
			}

		## **THE HUMANS INVOLVED, WHO ELECT**: the human participants and the
		## owners of the agents and bots, each once.
		involved : ConvAccess.Conv -> List(Principal.GitHubId)
		involved = |ConvAccess.Conv.(c)|
			List.fold(
				c.participants,
				[],
				|kept, p| {
					human = Principal.answers_to(p)
					if List.contains(kept, human) kept else List.append(kept, human)
				},
			)

		## **THE ONE TRANSITION**: `human` elects a visibility.
		## `AlwaysPrivate` for a conversation of humans alone, which has no
		## election; `NotInvolved` for a human who is neither in it nor owns
		## an agent or bot in it. Electing private withdraws a public
		## election, and makes the conversation private at once.
		elect : ConvAccess.Conv,
		ConvAccess.Election -> Try(
			ConvAccess.Conv,
			[AlwaysPrivate, NotInvolved],
		)
		elect = |conv, { human, visibility }| {
			ConvAccess.Conv.(c) = conv
			match conv.kind() {
				HumansOnly => Err(AlwaysPrivate)
				WithAgents =>
					if !List.contains(conv.involved(), human) {
						Err(NotInvolved)
					} else {
						others = List.keep_if(c.public_by, |h| h != human)
						match visibility {
							Public => Ok(ConvAccess.Conv.({ ..c, public_by: others.append(human) }))
							Private => Ok(ConvAccess.Conv.({ ..c, public_by: others }))
						}
					}
			}
		}

		## **ITS VISIBILITY NOW**: private for humans alone; otherwise
		## public only while every human involved has elected public.
		visibility : ConvAccess.Conv -> [Private, Public]
		visibility = |conv| {
			ConvAccess.Conv.(c) = conv
			match conv.kind() {
				HumansOnly => Private
				WithAgents =>
					if List.all(conv.involved(), |h| c.public_by.contains(h)) Public else Private
			}
		}

		## The conversation as Access decides on it.
		resource : ConvAccess.Conv -> Access.Resource(ConvAccess.ConvId)
		resource = |conv| {
			ConvAccess.Conv.(c) = conv
			{
				id: c.id,
				participants: List.map(c.participants, Principal.id),
				visibility: conv.visibility(),
			}
		}
	}

	## **CAN THIS VIEWER SEE THIS CONVERSATION?** Access's rule on the
	## conversation's resource: a participant always; anyone signed in
	## while it is public; nobody signed out. An admin is no exception, and
	## neither is the owner of an agent or bot in it.
	can_see : Access.Viewer, ConvAccess.Conv -> Bool
	can_see = |viewer, conv| Access.can_see(viewer, conv.resource())

	## **CAN THIS VIEWER POST TO THIS CONVERSATION?** A participant only,
	## public or not.
	can_post : Access.Viewer, ConvAccess.Conv -> Bool
	can_post = |viewer, conv| Access.can_post(viewer, conv.resource())
}

# ── the cast
# Four humans, and five agents and bots, two of them a stranger's:
#   Ann     a member, owns AnnAgent
#   Bea     a member, owns BeaAgent and BeaBot
#   Cal     an ADMIN, in none of the conversations and owning nothing in them
#   Dee     a member, unrelated: owns DeeAgent and DeeBot, in none of them
# and `Out`, nobody signed in.
Who : [
	Out,
	Ann,
	Bea,
	Cal,
	Dee,
	AnnAgent,
	BeaAgent,
	BeaBot,
	DeeAgent,
	DeeBot,
]

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

principal : Who -> Principal
principal = |who|
	match who {
		Out => crash "principal: nobody signed in is no principal"
		Ann => person(1, Member)
		Bea => person(2, Member)
		Cal => person(3, Admin)
		Dee => person(4, Member)
		AnnAgent => owned(Agent, { id: 1, owner: 1 })
		BeaAgent => owned(Agent, { id: 2, owner: 2 })
		BeaBot => owned(Bot, { id: 3, owner: 2 })
		DeeAgent => owned(Agent, { id: 4, owner: 4 })
		DeeBot => owned(Bot, { id: 5, owner: 4 })
	}

viewer : Who -> Access.Viewer
viewer = |who|
	match who {
		Out => SignedOut
		_ => SignedIn(Principal.id(principal(who)))
	}

## A conversation among the cast.
among : List(Who) -> ConvAccess.Conv
among = |people|
	match ConvAccess.Conv.start({ id: cid(1), participants: List.map(people, principal) }) {
		Ok(conv) => conv
		Err(NoParticipants) => crash "among: a test's conversation has participants"
	}

cid : U64 -> ConvAccess.ConvId
cid = |n|
	match ConvAccess.ConvId.from_u64(n) {
		Ok(id) => id
		Err(NotAnId) => crash "cid: a test's conversation id is not 0"
	}

## `human` elects `visibility`, in a test where that is allowed.
elected : ConvAccess.Conv, { human : Who, visibility : [Private, Public] } -> ConvAccess.Conv
elected = |conv, { human, visibility }|
	match conv.elect({ human: Principal.answers_to(principal(human)), visibility }) {
		Ok(next) => next
		Err(_) => crash "elected: a test's election is allowed"
	}

## The answers said as words, so each cell reads plainly.
sees : Who, ConvAccess.Conv -> [Visible, Hidden]
sees = |who, conv| if ConvAccess.can_see(viewer(who), conv) Visible else Hidden

posts : Who, ConvAccess.Conv -> [Writable, ReadOnly]
posts = |who, conv| if ConvAccess.can_post(viewer(who), conv) Writable else ReadOnly

# ── the conversations, in each election state
# hh        Ann and Bea: humans alone, always private, no election.
# ha_own    Ann and AnnAgent: Ann alone elects.
# ha_cross  Ann and BeaAgent: Ann and Bea elect.
# aa        AnnAgent and BeaAgent: their owners, Ann and Bea, elect.
# hb        Ann and BeaBot: Ann and Bea elect.
# A state's suffix says who has elected public now: `none`, `ann`, `bea`,
# `both`, or `withdrawn` (both elected, then Ann elected private again).
hh : ConvAccess.Conv
hh = among([Ann, Bea])

ha_own_none : ConvAccess.Conv
ha_own_none = among([Ann, AnnAgent])

ha_own_ann : ConvAccess.Conv
ha_own_ann = elected(ha_own_none, { human: Ann, visibility: Public })

ha_own_withdrawn : ConvAccess.Conv
ha_own_withdrawn = elected(ha_own_ann, { human: Ann, visibility: Private })

ha_cross_none : ConvAccess.Conv
ha_cross_none = among([Ann, BeaAgent])

ha_cross_ann : ConvAccess.Conv
ha_cross_ann = elected(ha_cross_none, { human: Ann, visibility: Public })

ha_cross_bea : ConvAccess.Conv
ha_cross_bea = elected(ha_cross_none, { human: Bea, visibility: Public })

ha_cross_both : ConvAccess.Conv
ha_cross_both = elected(ha_cross_ann, { human: Bea, visibility: Public })

ha_cross_withdrawn : ConvAccess.Conv
ha_cross_withdrawn = elected(ha_cross_both, { human: Ann, visibility: Private })

aa_none : ConvAccess.Conv
aa_none = among([AnnAgent, BeaAgent])

aa_ann : ConvAccess.Conv
aa_ann = elected(aa_none, { human: Ann, visibility: Public })

aa_bea : ConvAccess.Conv
aa_bea = elected(aa_none, { human: Bea, visibility: Public })

aa_both : ConvAccess.Conv
aa_both = elected(aa_ann, { human: Bea, visibility: Public })

aa_withdrawn : ConvAccess.Conv
aa_withdrawn = elected(aa_both, { human: Ann, visibility: Private })

hb_none : ConvAccess.Conv
hb_none = among([Ann, BeaBot])

hb_ann : ConvAccess.Conv
hb_ann = elected(hb_none, { human: Ann, visibility: Public })

hb_bea : ConvAccess.Conv
hb_bea = elected(hb_none, { human: Bea, visibility: Public })

hb_both : ConvAccess.Conv
hb_both = elected(hb_ann, { human: Bea, visibility: Public })

hb_withdrawn : ConvAccess.Conv
hb_withdrawn = elected(hb_both, { human: Ann, visibility: Private })

# ── the elections
# Humans alone have no election; a human uninvolved has none either.
## `who` tries to elect public, where that is refused.
refused : ConvAccess.Conv, Who -> Try(ConvAccess.ConvId, [AlwaysPrivate, NotInvolved])
refused = |conv, who|
	conv.elect({ human: Principal.answers_to(principal(who)), visibility: Public })
		.map_ok(ConvAccess.Conv.id)

nobody : Try(ConvAccess.ConvId, [NoParticipants])
nobody = ConvAccess.Conv.start({ id: cid(1), participants: [] }).map_ok(ConvAccess.Conv.id)

expect refused(hh, Ann) == Err(AlwaysPrivate)
expect refused(hh, Cal) == Err(AlwaysPrivate)
expect refused(ha_own_none, Bea) == Err(NotInvolved)
expect refused(aa_none, Cal) == Err(NotInvolved)
expect refused(hb_none, Dee) == Err(NotInvolved)
expect nobody == Err(NoParticipants)
# Who is involved: participants that are humans, and owners, each once.
expect ha_cross_none.involved() == [gid(1), gid(2)]
expect aa_none.involved() == [gid(1), gid(2)]
expect among([BeaAgent, BeaBot]).involved() == [gid(2)]
expect among([Ann, Ann]).resource().participants == [Principal.Id.Human(gid(1))]
# Electing public twice is one election; one withdrawal undoes it.
expect elected(ha_own_ann, { human: Ann, visibility: Public }).visibility() == Public
ha_own_twice : ConvAccess.Conv
ha_own_twice = elected(ha_own_ann, { human: Ann, visibility: Public })

expect elected(ha_own_twice, { human: Ann, visibility: Private }).visibility() == Private
# Electing private when already private changes nothing.
expect elected(aa_none, { human: Ann, visibility: Private }).visibility() == Private

# Each state's visibility, stated.
expect hh.visibility() == Private
expect ha_own_none.visibility() == Private
expect ha_own_ann.visibility() == Public
expect ha_own_withdrawn.visibility() == Private
expect ha_cross_none.visibility() == Private
expect ha_cross_ann.visibility() == Private
expect ha_cross_bea.visibility() == Private
expect ha_cross_both.visibility() == Public
expect ha_cross_withdrawn.visibility() == Private
expect aa_none.visibility() == Private
expect aa_ann.visibility() == Private
expect aa_bea.visibility() == Private
expect aa_both.visibility() == Public
expect aa_withdrawn.visibility() == Private
expect hb_none.visibility() == Private
expect hb_ann.visibility() == Private
expect hb_bea.visibility() == Private
expect hb_both.visibility() == Public
expect hb_withdrawn.visibility() == Private

# ── THE can_see TABLE
# Every viewer against every conversation in every election state, one
# cell a line, its answer written out. A private conversation is seen by
# its participants alone: not Cal the admin, not an owner who is not in it
# (Bea in ha_cross, aa and hb; Ann in aa), never `Out`. A public one is
# seen by everyone signed in, and still never by `Out`.

# hh: Ann and Bea; always private.
expect sees(Out, hh) == Hidden
expect sees(Ann, hh) == Visible
expect sees(Bea, hh) == Visible
expect sees(Cal, hh) == Hidden
expect sees(Dee, hh) == Hidden
expect sees(AnnAgent, hh) == Hidden
expect sees(BeaAgent, hh) == Hidden
expect sees(BeaBot, hh) == Hidden
expect sees(DeeAgent, hh) == Hidden
expect sees(DeeBot, hh) == Hidden

# ha_own, nobody elected public: private to Ann and AnnAgent.
expect sees(Out, ha_own_none) == Hidden
expect sees(Ann, ha_own_none) == Visible
expect sees(Bea, ha_own_none) == Hidden
expect sees(Cal, ha_own_none) == Hidden
expect sees(Dee, ha_own_none) == Hidden
expect sees(AnnAgent, ha_own_none) == Visible
expect sees(BeaAgent, ha_own_none) == Hidden
expect sees(BeaBot, ha_own_none) == Hidden
expect sees(DeeAgent, ha_own_none) == Hidden
expect sees(DeeBot, ha_own_none) == Hidden

# ha_own, Ann elected public: public, Ann being the only human involved.
expect sees(Out, ha_own_ann) == Hidden
expect sees(Ann, ha_own_ann) == Visible
expect sees(Bea, ha_own_ann) == Visible
expect sees(Cal, ha_own_ann) == Visible
expect sees(Dee, ha_own_ann) == Visible
expect sees(AnnAgent, ha_own_ann) == Visible
expect sees(BeaAgent, ha_own_ann) == Visible
expect sees(BeaBot, ha_own_ann) == Visible
expect sees(DeeAgent, ha_own_ann) == Visible
expect sees(DeeBot, ha_own_ann) == Visible

# ha_own, Ann elected public then withdrew: private to Ann and AnnAgent.
expect sees(Out, ha_own_withdrawn) == Hidden
expect sees(Ann, ha_own_withdrawn) == Visible
expect sees(Bea, ha_own_withdrawn) == Hidden
expect sees(Cal, ha_own_withdrawn) == Hidden
expect sees(Dee, ha_own_withdrawn) == Hidden
expect sees(AnnAgent, ha_own_withdrawn) == Visible
expect sees(BeaAgent, ha_own_withdrawn) == Hidden
expect sees(BeaBot, ha_own_withdrawn) == Hidden
expect sees(DeeAgent, ha_own_withdrawn) == Hidden
expect sees(DeeBot, ha_own_withdrawn) == Hidden

# ha_cross, nobody elected public: private to Ann and BeaAgent.
expect sees(Out, ha_cross_none) == Hidden
expect sees(Ann, ha_cross_none) == Visible
expect sees(Bea, ha_cross_none) == Hidden
expect sees(Cal, ha_cross_none) == Hidden
expect sees(Dee, ha_cross_none) == Hidden
expect sees(AnnAgent, ha_cross_none) == Hidden
expect sees(BeaAgent, ha_cross_none) == Visible
expect sees(BeaBot, ha_cross_none) == Hidden
expect sees(DeeAgent, ha_cross_none) == Hidden
expect sees(DeeBot, ha_cross_none) == Hidden

# ha_cross, Ann alone elected public: still private to Ann and BeaAgent.
expect sees(Out, ha_cross_ann) == Hidden
expect sees(Ann, ha_cross_ann) == Visible
expect sees(Bea, ha_cross_ann) == Hidden
expect sees(Cal, ha_cross_ann) == Hidden
expect sees(Dee, ha_cross_ann) == Hidden
expect sees(AnnAgent, ha_cross_ann) == Hidden
expect sees(BeaAgent, ha_cross_ann) == Visible
expect sees(BeaBot, ha_cross_ann) == Hidden
expect sees(DeeAgent, ha_cross_ann) == Hidden
expect sees(DeeBot, ha_cross_ann) == Hidden

# ha_cross, Bea alone elected public: still private to Ann and BeaAgent.
expect sees(Out, ha_cross_bea) == Hidden
expect sees(Ann, ha_cross_bea) == Visible
expect sees(Bea, ha_cross_bea) == Hidden
expect sees(Cal, ha_cross_bea) == Hidden
expect sees(Dee, ha_cross_bea) == Hidden
expect sees(AnnAgent, ha_cross_bea) == Hidden
expect sees(BeaAgent, ha_cross_bea) == Visible
expect sees(BeaBot, ha_cross_bea) == Hidden
expect sees(DeeAgent, ha_cross_bea) == Hidden
expect sees(DeeBot, ha_cross_bea) == Hidden

# ha_cross, both elected public: public.
expect sees(Out, ha_cross_both) == Hidden
expect sees(Ann, ha_cross_both) == Visible
expect sees(Bea, ha_cross_both) == Visible
expect sees(Cal, ha_cross_both) == Visible
expect sees(Dee, ha_cross_both) == Visible
expect sees(AnnAgent, ha_cross_both) == Visible
expect sees(BeaAgent, ha_cross_both) == Visible
expect sees(BeaBot, ha_cross_both) == Visible
expect sees(DeeAgent, ha_cross_both) == Visible
expect sees(DeeBot, ha_cross_both) == Visible

# ha_cross, both elected, then Ann withdrew: private to Ann and BeaAgent.
expect sees(Out, ha_cross_withdrawn) == Hidden
expect sees(Ann, ha_cross_withdrawn) == Visible
expect sees(Bea, ha_cross_withdrawn) == Hidden
expect sees(Cal, ha_cross_withdrawn) == Hidden
expect sees(Dee, ha_cross_withdrawn) == Hidden
expect sees(AnnAgent, ha_cross_withdrawn) == Hidden
expect sees(BeaAgent, ha_cross_withdrawn) == Visible
expect sees(BeaBot, ha_cross_withdrawn) == Hidden
expect sees(DeeAgent, ha_cross_withdrawn) == Hidden
expect sees(DeeBot, ha_cross_withdrawn) == Hidden

# aa, nobody elected public: private to AnnAgent and BeaAgent; their
# owners, not being in it, do not see it.
expect sees(Out, aa_none) == Hidden
expect sees(Ann, aa_none) == Hidden
expect sees(Bea, aa_none) == Hidden
expect sees(Cal, aa_none) == Hidden
expect sees(Dee, aa_none) == Hidden
expect sees(AnnAgent, aa_none) == Visible
expect sees(BeaAgent, aa_none) == Visible
expect sees(BeaBot, aa_none) == Hidden
expect sees(DeeAgent, aa_none) == Hidden
expect sees(DeeBot, aa_none) == Hidden

# aa, Ann alone elected public: still private to the two agents.
expect sees(Out, aa_ann) == Hidden
expect sees(Ann, aa_ann) == Hidden
expect sees(Bea, aa_ann) == Hidden
expect sees(Cal, aa_ann) == Hidden
expect sees(Dee, aa_ann) == Hidden
expect sees(AnnAgent, aa_ann) == Visible
expect sees(BeaAgent, aa_ann) == Visible
expect sees(BeaBot, aa_ann) == Hidden
expect sees(DeeAgent, aa_ann) == Hidden
expect sees(DeeBot, aa_ann) == Hidden

# aa, Bea alone elected public: still private to the two agents.
expect sees(Out, aa_bea) == Hidden
expect sees(Ann, aa_bea) == Hidden
expect sees(Bea, aa_bea) == Hidden
expect sees(Cal, aa_bea) == Hidden
expect sees(Dee, aa_bea) == Hidden
expect sees(AnnAgent, aa_bea) == Visible
expect sees(BeaAgent, aa_bea) == Visible
expect sees(BeaBot, aa_bea) == Hidden
expect sees(DeeAgent, aa_bea) == Hidden
expect sees(DeeBot, aa_bea) == Hidden

# aa, both owners elected public: public.
expect sees(Out, aa_both) == Hidden
expect sees(Ann, aa_both) == Visible
expect sees(Bea, aa_both) == Visible
expect sees(Cal, aa_both) == Visible
expect sees(Dee, aa_both) == Visible
expect sees(AnnAgent, aa_both) == Visible
expect sees(BeaAgent, aa_both) == Visible
expect sees(BeaBot, aa_both) == Visible
expect sees(DeeAgent, aa_both) == Visible
expect sees(DeeBot, aa_both) == Visible

# aa, both elected, then Ann withdrew: private to the two agents.
expect sees(Out, aa_withdrawn) == Hidden
expect sees(Ann, aa_withdrawn) == Hidden
expect sees(Bea, aa_withdrawn) == Hidden
expect sees(Cal, aa_withdrawn) == Hidden
expect sees(Dee, aa_withdrawn) == Hidden
expect sees(AnnAgent, aa_withdrawn) == Visible
expect sees(BeaAgent, aa_withdrawn) == Visible
expect sees(BeaBot, aa_withdrawn) == Hidden
expect sees(DeeAgent, aa_withdrawn) == Hidden
expect sees(DeeBot, aa_withdrawn) == Hidden

# hb, nobody elected public: private to Ann and BeaBot.
expect sees(Out, hb_none) == Hidden
expect sees(Ann, hb_none) == Visible
expect sees(Bea, hb_none) == Hidden
expect sees(Cal, hb_none) == Hidden
expect sees(Dee, hb_none) == Hidden
expect sees(AnnAgent, hb_none) == Hidden
expect sees(BeaAgent, hb_none) == Hidden
expect sees(BeaBot, hb_none) == Visible
expect sees(DeeAgent, hb_none) == Hidden
expect sees(DeeBot, hb_none) == Hidden

# hb, Ann alone elected public: still private to Ann and BeaBot.
expect sees(Out, hb_ann) == Hidden
expect sees(Ann, hb_ann) == Visible
expect sees(Bea, hb_ann) == Hidden
expect sees(Cal, hb_ann) == Hidden
expect sees(Dee, hb_ann) == Hidden
expect sees(AnnAgent, hb_ann) == Hidden
expect sees(BeaAgent, hb_ann) == Hidden
expect sees(BeaBot, hb_ann) == Visible
expect sees(DeeAgent, hb_ann) == Hidden
expect sees(DeeBot, hb_ann) == Hidden

# hb, Bea alone elected public: still private to Ann and BeaBot.
expect sees(Out, hb_bea) == Hidden
expect sees(Ann, hb_bea) == Visible
expect sees(Bea, hb_bea) == Hidden
expect sees(Cal, hb_bea) == Hidden
expect sees(Dee, hb_bea) == Hidden
expect sees(AnnAgent, hb_bea) == Hidden
expect sees(BeaAgent, hb_bea) == Hidden
expect sees(BeaBot, hb_bea) == Visible
expect sees(DeeAgent, hb_bea) == Hidden
expect sees(DeeBot, hb_bea) == Hidden

# hb, both elected public: public.
expect sees(Out, hb_both) == Hidden
expect sees(Ann, hb_both) == Visible
expect sees(Bea, hb_both) == Visible
expect sees(Cal, hb_both) == Visible
expect sees(Dee, hb_both) == Visible
expect sees(AnnAgent, hb_both) == Visible
expect sees(BeaAgent, hb_both) == Visible
expect sees(BeaBot, hb_both) == Visible
expect sees(DeeAgent, hb_both) == Visible
expect sees(DeeBot, hb_both) == Visible

# hb, both elected, then Ann withdrew: private to Ann and BeaBot.
expect sees(Out, hb_withdrawn) == Hidden
expect sees(Ann, hb_withdrawn) == Visible
expect sees(Bea, hb_withdrawn) == Hidden
expect sees(Cal, hb_withdrawn) == Hidden
expect sees(Dee, hb_withdrawn) == Hidden
expect sees(AnnAgent, hb_withdrawn) == Hidden
expect sees(BeaAgent, hb_withdrawn) == Hidden
expect sees(BeaBot, hb_withdrawn) == Visible
expect sees(DeeAgent, hb_withdrawn) == Hidden
expect sees(DeeBot, hb_withdrawn) == Hidden

# ── THE can_post TABLE
# Seeing is not posting: each conversation private and public, and only
# its participants may post in either.

# hh: Ann and Bea.
expect posts(Out, hh) == ReadOnly
expect posts(Ann, hh) == Writable
expect posts(Bea, hh) == Writable
expect posts(Cal, hh) == ReadOnly
expect posts(Dee, hh) == ReadOnly
expect posts(AnnAgent, hh) == ReadOnly
expect posts(BeaAgent, hh) == ReadOnly
expect posts(BeaBot, hh) == ReadOnly
expect posts(DeeAgent, hh) == ReadOnly
expect posts(DeeBot, hh) == ReadOnly

# ha_own, private: Ann and AnnAgent.
expect posts(Out, ha_own_none) == ReadOnly
expect posts(Ann, ha_own_none) == Writable
expect posts(Bea, ha_own_none) == ReadOnly
expect posts(Cal, ha_own_none) == ReadOnly
expect posts(Dee, ha_own_none) == ReadOnly
expect posts(AnnAgent, ha_own_none) == Writable
expect posts(BeaAgent, ha_own_none) == ReadOnly
expect posts(BeaBot, ha_own_none) == ReadOnly
expect posts(DeeAgent, ha_own_none) == ReadOnly
expect posts(DeeBot, ha_own_none) == ReadOnly

# ha_own, public: still Ann and AnnAgent.
expect posts(Out, ha_own_ann) == ReadOnly
expect posts(Ann, ha_own_ann) == Writable
expect posts(Bea, ha_own_ann) == ReadOnly
expect posts(Cal, ha_own_ann) == ReadOnly
expect posts(Dee, ha_own_ann) == ReadOnly
expect posts(AnnAgent, ha_own_ann) == Writable
expect posts(BeaAgent, ha_own_ann) == ReadOnly
expect posts(BeaBot, ha_own_ann) == ReadOnly
expect posts(DeeAgent, ha_own_ann) == ReadOnly
expect posts(DeeBot, ha_own_ann) == ReadOnly

# ha_cross, private: Ann and BeaAgent; Bea, the owner, may not.
expect posts(Out, ha_cross_none) == ReadOnly
expect posts(Ann, ha_cross_none) == Writable
expect posts(Bea, ha_cross_none) == ReadOnly
expect posts(Cal, ha_cross_none) == ReadOnly
expect posts(Dee, ha_cross_none) == ReadOnly
expect posts(AnnAgent, ha_cross_none) == ReadOnly
expect posts(BeaAgent, ha_cross_none) == Writable
expect posts(BeaBot, ha_cross_none) == ReadOnly
expect posts(DeeAgent, ha_cross_none) == ReadOnly
expect posts(DeeBot, ha_cross_none) == ReadOnly

# ha_cross, public: still Ann and BeaAgent.
expect posts(Out, ha_cross_both) == ReadOnly
expect posts(Ann, ha_cross_both) == Writable
expect posts(Bea, ha_cross_both) == ReadOnly
expect posts(Cal, ha_cross_both) == ReadOnly
expect posts(Dee, ha_cross_both) == ReadOnly
expect posts(AnnAgent, ha_cross_both) == ReadOnly
expect posts(BeaAgent, ha_cross_both) == Writable
expect posts(BeaBot, ha_cross_both) == ReadOnly
expect posts(DeeAgent, ha_cross_both) == ReadOnly
expect posts(DeeBot, ha_cross_both) == ReadOnly

# aa, private: the two agents.
expect posts(Out, aa_none) == ReadOnly
expect posts(Ann, aa_none) == ReadOnly
expect posts(Bea, aa_none) == ReadOnly
expect posts(Cal, aa_none) == ReadOnly
expect posts(Dee, aa_none) == ReadOnly
expect posts(AnnAgent, aa_none) == Writable
expect posts(BeaAgent, aa_none) == Writable
expect posts(BeaBot, aa_none) == ReadOnly
expect posts(DeeAgent, aa_none) == ReadOnly
expect posts(DeeBot, aa_none) == ReadOnly

# aa, public: still the two agents.
expect posts(Out, aa_both) == ReadOnly
expect posts(Ann, aa_both) == ReadOnly
expect posts(Bea, aa_both) == ReadOnly
expect posts(Cal, aa_both) == ReadOnly
expect posts(Dee, aa_both) == ReadOnly
expect posts(AnnAgent, aa_both) == Writable
expect posts(BeaAgent, aa_both) == Writable
expect posts(BeaBot, aa_both) == ReadOnly
expect posts(DeeAgent, aa_both) == ReadOnly
expect posts(DeeBot, aa_both) == ReadOnly

# hb, private: Ann and BeaBot.
expect posts(Out, hb_none) == ReadOnly
expect posts(Ann, hb_none) == Writable
expect posts(Bea, hb_none) == ReadOnly
expect posts(Cal, hb_none) == ReadOnly
expect posts(Dee, hb_none) == ReadOnly
expect posts(AnnAgent, hb_none) == ReadOnly
expect posts(BeaAgent, hb_none) == ReadOnly
expect posts(BeaBot, hb_none) == Writable
expect posts(DeeAgent, hb_none) == ReadOnly
expect posts(DeeBot, hb_none) == ReadOnly

# hb, public: still Ann and BeaBot.
expect posts(Out, hb_both) == ReadOnly
expect posts(Ann, hb_both) == Writable
expect posts(Bea, hb_both) == ReadOnly
expect posts(Cal, hb_both) == ReadOnly
expect posts(Dee, hb_both) == ReadOnly
expect posts(AnnAgent, hb_both) == ReadOnly
expect posts(BeaAgent, hb_both) == ReadOnly
expect posts(BeaBot, hb_both) == Writable
expect posts(DeeAgent, hb_both) == ReadOnly
expect posts(DeeBot, hb_both) == ReadOnly
