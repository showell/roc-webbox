## **WHO MAY SEE A RESOURCE, AND WHO MAY ADD TO IT** (the Roc chat's auth
## design, section 4), decided against a resource the core knows only by
## what it needs: its id, its participants and its visibility. What the
## resource is (a conversation, a database, a file system) and how its
## visibility is worked out are its layer's: the chat's is ConvAccess.roc,
## where a conversation's elections make it public or private. Pure.
import Principal

Access := [].{

	## Who is asking: nobody signed in, or one principal.
	Viewer : [SignedOut, SignedIn(Principal.Id)]

	## **A RESOURCE, AS THE CORE DECIDES ON IT**: its id (the layer's own
	## type: the chat's ConvId), the principals in it, and its visibility as
	## its layer worked it out. Private or public, no more granular.
	Resource(id) : {
		id : id,
		participants : List(Principal.Id),
		visibility : [Private, Public],
	}

	## **CAN THIS VIEWER SEE THIS RESOURCE?** A participant always can; a
	## public resource, any signed-in principal can; nobody signed out can,
	## whatever its visibility. Nothing else grants sight: an admin's role
	## is no part of it (an admin manages accounts and does not read
	## private conversations), and neither is owning a participant.
	can_see : Viewer, Resource(id) -> Bool
	can_see = |viewer, resource|
		match viewer {
			SignedOut => Bool.False
			SignedIn(who) =>
				if Access.is_participant(resource, who) {
					Bool.True
				} else {
					match resource.visibility {
						Public => Bool.True
						Private => Bool.False
					}
				}
		}

	## **CAN THIS VIEWER ADD TO THIS RESOURCE?** Only a participant: seeing
	## is not posting, so public means readable, never writable.
	can_post : Viewer, Resource(id) -> Bool
	can_post = |viewer, resource|
		match viewer {
			SignedOut => Bool.False
			SignedIn(who) => Access.is_participant(resource, who)
		}

	## `who` is among the resource's participants.
	is_participant : Resource(id), Principal.Id -> Bool
	is_participant = |resource, who| List.contains(resource.participants, who)
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

# **THE CORE'S OWN TABLE**, on a resource that is not a conversation: a
# file a file system names by its path (its id a Str), held by one human.
# The viewers are nobody signed in, the file's participant, and a stranger.
holder : Access.Viewer
holder = SignedIn(Principal.Id.Human(gid(1)))

stranger : Access.Viewer
stranger = SignedIn(Principal.Id.Human(gid(2)))

private_file : Access.Resource(Str)
private_file = {
	id: "/notes/plan.md",
	participants: [Principal.Id.Human(gid(1))],
	visibility: Private,
}

public_file : Access.Resource(Str)
public_file = { ..private_file, visibility: Public }

# Seeing.
expect sees(SignedOut, private_file) == Hidden
expect sees(holder, private_file) == Visible
expect sees(stranger, private_file) == Hidden
expect sees(SignedOut, public_file) == Hidden
expect sees(holder, public_file) == Visible
expect sees(stranger, public_file) == Visible

# Adding to it: the participant alone, public or not.
expect posts(SignedOut, private_file) == ReadOnly
expect posts(holder, private_file) == Writable
expect posts(stranger, private_file) == ReadOnly
expect posts(SignedOut, public_file) == ReadOnly
expect posts(holder, public_file) == Writable
expect posts(stranger, public_file) == ReadOnly
