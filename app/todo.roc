## A TODO LIST, served by webbox: the app the platform's host calls for each
## request under /api/. Each visitor has their own list, one file,
## lists/<user>.json in the folder the host gives it (`user` is the visitor's
## id, which the host's signed cookie names), read and written as each
## request runs.
##
##   GET    /api/todos              the list
##   POST   /api/todos              a new item, its text the body
##   POST   /api/todos/<id>/toggle  done, or not done again
##   DELETE /api/todos/<id>         gone
##
## Every answer that changes nothing or something is the whole list, so the
## page draws what it is given.
app [handle!] { pf: platform "../platform/main.roc" }

import pf.File
import pf.Http

Todo : { id : U64, text : Str, done : Bool }

Todos : { next_id : U64, items : List(Todo) }

## The visitor's list's file.
store_path : Str -> Str
store_path = |user| "lists/${user}.json"

## The list as the file holds it; a list with nothing in it when there is no
## file yet. A file that is not one, or one that could not be read, is an
## error, never an empty list: the next write would build on that.
load! : Str => Try(Todos, [Unreadable(Str)])
load! = |user| match File.read!(store_path(user)) {
	Ok(text) => match Json.parse(text) {
		Ok(todos) => Ok(todos)
		Err(_) => Err(Unreadable("${store_path(user)} is not a list of todos"))
	}
	Err(NotFound(_)) => Ok({ next_id: 1, items: [] })
	Err(ReadFailed(why)) => Err(Unreadable(why))
}

save! : Str, Todos => Try({}, [WriteFailed(Str)])
save! = |user, todos| File.write!(store_path(user), Json.to_str(todos))

## The list as the page takes it.
listed : Todos -> Http.Response
listed = |todos| Http.json(200, Json.to_str(todos.items))

## Changes the list and answers with it, or says why not.
change! : Str, (Todos -> Try(Todos, [NoSuchItem(U64), Empty])) => Http.Response
change! = |user, edit| match load!(user) {
	Err(Unreadable(why)) => Http.text(500, why)
	Ok(todos) => match edit(todos) {
		Err(NoSuchItem(id)) => Http.text(404, "no item ${U64.to_str(id)}")
		Err(Empty) => Http.text(400, "an item needs some text")
		Ok(changed) => match save!(user, changed) {
			Ok({}) => listed(changed)
			Err(WriteFailed(why)) => Http.text(500, why)
		}
	}
}

add : Str -> (Todos -> Try(Todos, [NoSuchItem(U64), Empty]))
add = |text| |todos| {
	trimmed = Str.trim(text)
	if Str.is_empty(trimmed) {
		Err(Empty)
	} else {
		Ok({ next_id: todos.next_id + 1, items: List.append(todos.items, { id: todos.next_id, text: trimmed, done: Bool.False }) })
	}
}

holds : Todos, U64 -> Bool
holds = |todos, id| List.len(List.keep_if(todos.items, |t| t.id == id)) > 0

toggle : U64 -> (Todos -> Try(Todos, [NoSuchItem(U64), Empty]))
toggle = |id| |todos|
	if holds(todos, id) {
		Ok({ ..todos, items: List.map(todos.items, |t| if t.id == id { ..t, done: !t.done } else t) })
	} else {
		Err(NoSuchItem(id))
	}

remove : U64 -> (Todos -> Try(Todos, [NoSuchItem(U64), Empty]))
remove = |id| |todos|
	if holds(todos, id) {
		Ok({ ..todos, items: List.drop_if(todos.items, |t| t.id == id) })
	} else {
		Err(NoSuchItem(id))
	}

handle! : Http.Request => Http.Response
handle! = |req| {
	parts = List.drop_if(Str.split_on(req.path, "/"), Str.is_empty)
	match parts {
		["api", "todos"] =>
			if req.method == "GET" {
				match load!(req.user) {
					Ok(todos) => listed(todos)
					Err(Unreadable(why)) => Http.text(500, why)
				}
			} else if req.method == "POST" {
				change!(req.user, add(req.body))
			} else {
				Http.text(405, "GET or POST")
			}
		["api", "todos", id_text, "toggle"] if req.method == "POST" =>
			match U64.from_str(id_text) {
				Ok(id) => change!(req.user, toggle(id))
				Err(_) => Http.text(404, "no item ${id_text}")
			}
		["api", "todos", id_text] if req.method == "DELETE" =>
			match U64.from_str(id_text) {
				Ok(id) => change!(req.user, remove(id))
				Err(_) => Http.text(404, "no item ${id_text}")
			}
		_ => Http.text(404, "no such route: ${req.method} ${req.path}")
	}
}
