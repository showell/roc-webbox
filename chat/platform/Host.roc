## THE HOST'S ANSWERS, AS EFFECTS: each is asked when the app asks it, inside
## the request's call.
Host := [].{
	## Whether the one asking may use the chat: a member, or the agent
	## (angry-gopher's `users.principalAuthorized` of who the request's
	## cookie or API key names). Asked after the static assets, which anyone
	## may fetch, so a request for one does no identity reads.
	member! : {} => Bool
}
