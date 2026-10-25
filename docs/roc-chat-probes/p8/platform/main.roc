platform ""
	requires {
		[Model : model] for program : {
			init! : {} => model,
			handle! : model, List(U8) => (model, List(U8)),
		}
	}
	exposes [Resp]
	packages {}
	provides { "roc_init": init_for_host!, "roc_handle": handle_for_host!, "roc_nominal": nominal_for_host }
	targets: {
		x64musl: { inputs: [app], output: Archive },
	}

import Resp

init_for_host! : {} => Box(Model)
init_for_host! = |{}| Box.box((program.init!)({}))

handle_for_host! : Box(Model), List(U8) => { model : Box(Model), out : List(U8) }
handle_for_host! = |boxed, input| {
	(m, out) = (program.handle!)(Box.unbox(boxed), input)
	{ model: Box.box(m), out }
}

nominal_for_host : List(U8) -> Resp
nominal_for_host = |b| Resp.new(b)
