## **WHO MAY SEE A RESOURCE, AND WHO MAY ADD TO IT** (the Roc chat's auth
## design, sections 4 and 11), decided against a resource the core knows
## only by what it needs: its id, its participants, the humans they answer
## to, and its visibility. What the resource is (a conversation, a database,
## a file system) and how its visibility and owners are worked out are its
## layer's: the chat's is ConvAccess.roc, where a conversation's elections
## make it public or private and the accounts name each agent's owner. A
## decision that a key asks (ApiKey.decide) takes the layer's own opaque
## value, never this record, so a handler cannot hand it a record it made
## public itself. Pure.
import Principal

Access := [].{

	## Who is asking: nobody signed in, or one principal.
	Viewer : [SignedOut, SignedIn(Principal.Id)]

	## **A RESOURCE, AS THE CORE DECIDES ON IT**: its id (the layer's own
	## type: the chat's ConvId), the principals in it, the humans they
	## answer to (the human participants, and the owners of its agents and
	## bots, as the accounts say now), and its visibility as its layer
	## worked it out. Private or public, no more granular.
	Resource(id) : {
		id : id,
		participants : List(Principal.Id),
		involved : List(Principal.GitHubId),
		visibility : [Private, Public],
	}

	## **CAN THIS VIEWER SEE THIS RESOURCE?** A participant always can, and
	## so can the human it answers to (an owner can mint a key acting as
	## their agent, so hiding the agent's resources from them would be no
	## barrier); a public resource, any signed-in human or agent can, never
	## a bot that is not in it; nobody signed out can, whatever its
	## visibility. An admin's role is no part of it: an admin manages
	## accounts and does not read private conversations.
	can_see : Viewer, Resource(id) -> Bool
	can_see = |viewer, resource|
		match viewer {
			SignedOut => Bool.False
			SignedIn(who) =>
				if Access.is_answerable(resource, who) {
					Bool.True
				} else {
					match (resource.visibility, who) {
						(Public, Human(_)) | (Public, Agent(_)) => Bool.True
						(Public, Bot(_)) | (Private, _) => Bool.False
					}
				}
		}

	## **CAN THIS VIEWER ADD TO THIS RESOURCE?** A participant, or the
	## human it answers to: seeing is not posting, so public means
	## readable, never writable.
	can_post : Viewer, Resource(id) -> Bool
	can_post = |viewer, resource|
		match viewer {
			SignedOut => Bool.False
			SignedIn(who) => Access.is_answerable(resource, who)
		}

	## `who` is among the resource's participants, or is a human one of
	## them answers to.
	is_answerable : Resource(id), Principal.Id -> Bool
	is_answerable = |resource, who|
		if List.contains(resource.participants, who) {
			Bool.True
		} else {
			match who {
				Human(g) => List.contains(resource.involved, g)
				Agent(_) | Bot(_) => Bool.False
			}
		}
}

## A test's answer, said as a word, so a table cell reads plainly.
sees : Access.Viewer, Access.Resource(Str) -> [Visible, Hidden]
sees = |viewer, resource| if Access.can_see(viewer, resource) Visible else Hidden

posts : Access.Viewer, Access.Resource(Str) -> [Writable, ReadOnly]
posts = |viewer, resource| if Access.can_post(viewer, resource) Writable else ReadOnly

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

# **THE CORE'S OWN TABLE**, on a resource that is not a conversation: a
# file a file system names by its path (its id a Str), held by one human,
# and a file held by one agent. The viewers are nobody signed in, the
# human holder, a stranger, the agent holder, its owner, a stranger's
# agent, and a stranger's bot.
holder : Access.Viewer
holder = SignedIn(Principal.Id.Human(gid(1)))

stranger : Access.Viewer
stranger = SignedIn(Principal.Id.Human(gid(2)))

agent_holder : Access.Viewer
agent_holder = SignedIn(Principal.Id.Agent(aid(1)))

owner : Access.Viewer
owner = SignedIn(Principal.Id.Human(gid(3)))

other_agent : Access.Viewer
other_agent = SignedIn(Principal.Id.Agent(aid(2)))

other_bot : Access.Viewer
other_bot = SignedIn(Principal.Id.Bot(aid(3)))

private_file : Access.Resource(Str)
private_file = {
	id: "/notes/plan.md",
	participants: [Principal.Id.Human(gid(1))],
	involved: [gid(1)],
	visibility: Private,
}

public_file : Access.Resource(Str)
public_file = { ..private_file, visibility: Public }

## Held by agent 1, whom human 3 owns.
agents_file : Access.Resource(Str)
agents_file = {
	id: "/notes/agent.md",
	participants: [Principal.Id.Agent(aid(1))],
	involved: [gid(3)],
	visibility: Private,
}

# Seeing.
expect sees(SignedOut, private_file) == Hidden
expect sees(holder, private_file) == Visible
expect sees(stranger, private_file) == Hidden
expect sees(other_agent, private_file) == Hidden
expect sees(other_bot, private_file) == Hidden
expect sees(SignedOut, public_file) == Hidden
expect sees(holder, public_file) == Visible
expect sees(stranger, public_file) == Visible
expect sees(other_agent, public_file) == Visible
expect sees(other_bot, public_file) == Hidden
expect sees(agent_holder, agents_file) == Visible
expect sees(owner, agents_file) == Visible
expect sees(stranger, agents_file) == Hidden
expect sees(other_agent, agents_file) == Hidden

# Adding to it: the participant, and the human it answers to, public or not.
expect posts(SignedOut, private_file) == ReadOnly
expect posts(holder, private_file) == Writable
expect posts(stranger, private_file) == ReadOnly
expect posts(SignedOut, public_file) == ReadOnly
expect posts(holder, public_file) == Writable
expect posts(stranger, public_file) == ReadOnly
expect posts(other_agent, public_file) == ReadOnly
expect posts(agent_holder, agents_file) == Writable
expect posts(owner, agents_file) == Writable
expect posts(stranger, agents_file) == ReadOnly
