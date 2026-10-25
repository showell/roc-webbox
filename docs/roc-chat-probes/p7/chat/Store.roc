import pf.Markdown
import pf.Host
import ./Codec

Store :: [].{
	render_all! : List(Str) => List(Str)
	render_all! = |bodies| {
		var $out = []
		for b in bodies {
			Host.log!("rendering ${b}")
			$out = List.append($out, Markdown.render!(b))
		}
		$out
	}

	render_all_try! : List(Str) => Try(List(Str), [Nope])
	render_all_try! = |bodies| List.map_try!(bodies, |b| Ok(Markdown.render!(b)))

	log_each! : List(Str) => {}
	log_each! = |xs| List.for_each!(xs, |x| Host.log!("each ${x}"))

	count_blocks : Str -> U64
	count_blocks = |t| List.len(Codec.blocks(t))
}
